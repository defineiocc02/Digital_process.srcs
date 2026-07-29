"""Behavioral validation for the current SAR ADC V3 foreground calibration RTL.

This script is intentionally tied to the delivered RTL contract:

* `sar_calib_ctrl_serial.sv`:
  - bit targets 6..19
  - trusted lower bits 0..5
  - P/N measurement phases
  - bit-18/19 protection compensation
  - Q8 recursive writeback
* `sar_reconstruction.sv`:
  - raw bit contribution is +W / -W
  - differential divide-by-two
  - Q8 residue/rounding/shift
  - signed 16-bit saturation

The model is not a transistor-level or AMS model. It validates whether the
current digital calibration algorithm improves reconstruction when the same
physical decision stream is decoded by nominal, calibrated, and oracle weights.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple

import matplotlib.pyplot as plt
import numpy as np


IDEAL_WEIGHT_LSB = np.array(
    [
        1.00,
        2.00,
        4.00,
        8.00,
        16.00,
        32.00,
        33.53,
        67.05,
        134.10,
        268.20,
        316.91,
        316.91,
        633.81,
        1267.63,
        2535.25,
        5031.09,
        5031.09,
        10062.17,
        20124.35,
        40248.69,
    ],
    dtype=float,
)


@dataclass(frozen=True)
class ValidationConfig:
    cap_num: int = 20
    frac_bits: int = 8
    output_bits: int = 16
    max_calib_bit: int = 5
    avg_loops: int = 32
    comp_wait_cyc: int = 16
    ref_weight_lsb_q8: int = 256

    seed: int = 20260729
    n_chips: int = 32
    n_fft: int = 8192
    fs_hz: float = 1.0e6
    fin_target_hz: float = 19000.0
    sine_amplitude_code: float = 0.82 * 32767.0
    ramp_points: int = 4096
    ramp_amplitude_code: float = 0.86 * 32767.0

    low_mismatch_sigma: float = 0.0015
    high_mismatch_sigma: float = 0.0300
    comparator_offset_lsb: float = 5.0
    comparator_noise_lsb: float = 0.50


@dataclass
class ChipResult:
    chip_id: int
    decoder: str
    weight_rmse_lsb: float
    weight_rmse_gain_aligned_lsb: float
    weight_max_abs_gain_aligned_lsb: float
    static_error_rms_code: float
    static_error_max_abs_code: float
    static_backsteps: int
    dynamic_sndr_db: float
    dynamic_snr_db: float
    dynamic_sfdr_db: float
    dynamic_thd_db: float
    dynamic_enob: float
    saturation_fraction: float


def ideal_weight_q8(cfg: ValidationConfig) -> np.ndarray:
    return np.rint(IDEAL_WEIGHT_LSB * (1 << cfg.frac_bits)).astype(np.int64)


def stable_rng(cfg: ValidationConfig, *items: int) -> np.random.Generator:
    return np.random.default_rng(np.random.SeedSequence([cfg.seed, *items]))


def manufacture_chip_q8(cfg: ValidationConfig, chip_id: int) -> np.ndarray:
    """Create a deterministic virtual chip using the same sigma split as the TB."""

    rng = stable_rng(cfg, 100, chip_id)
    nominal = ideal_weight_q8(cfg).astype(float)
    sigma = np.full(cfg.cap_num, cfg.high_mismatch_sigma, dtype=float)
    sigma[: cfg.max_calib_bit + 1] = cfg.low_mismatch_sigma
    mismatch = rng.normal(0.0, sigma)
    return nominal * (1.0 + mismatch)


def protect_code(sar_code: np.ndarray, target_bit: int, cfg: ValidationConfig) -> np.ndarray:
    protected = np.array(sar_code, dtype=bool, copy=True)
    protect_start = cfg.cap_num - 2
    protect_low = cfg.cap_num - 3
    if target_bit == protect_start:
        protected[protect_low] = True
    elif target_bit == cfg.cap_num - 1:
        protected[protect_start] = True
        protected[protect_low] = True
    return protected


def comparator_decision(
    dac_p_force: np.ndarray,
    dac_n_force: np.ndarray,
    physical_q8: np.ndarray,
    cfg: ValidationConfig,
    rng: np.random.Generator,
) -> bool:
    vp = float(np.sum(physical_q8[dac_p_force]))
    vn = float(np.sum(physical_q8[dac_n_force]))
    offset = cfg.comparator_offset_lsb * (1 << cfg.frac_bits)
    noise = cfg.comparator_noise_lsb * (1 << cfg.frac_bits) * rng.normal()
    return (vp - vn + offset + noise) > 0.0


def rtl_phase_search(
    target_bit: int,
    phase: str,
    shadow_q8: np.ndarray,
    physical_q8: np.ndarray,
    cfg: ValidationConfig,
    rng: np.random.Generator,
) -> Tuple[np.ndarray, int]:
    """Mirror the RTL SAR search and serial accumulation for one P/N phase."""

    sar_code = np.zeros(cfg.cap_num, dtype=bool)
    protect_search_top = cfg.cap_num - 4
    if target_bit >= cfg.cap_num - 2:
        sar_ptr = protect_search_top
    else:
        sar_ptr = target_bit - 1

    while True:
        sar_code[sar_ptr] = True
        target_drive = np.zeros(cfg.cap_num, dtype=bool)
        target_drive[target_bit] = True
        protected = protect_code(sar_code, target_bit, cfg)

        if phase == "P":
            comp_out = comparator_decision(target_drive, protected, physical_q8, cfg, rng)
            if not comp_out:
                sar_code[sar_ptr] = False
        elif phase == "N":
            comp_out = comparator_decision(protected, target_drive, physical_q8, cfg, rng)
            if comp_out:
                sar_code[sar_ptr] = False
        else:
            raise ValueError(f"unsupported phase {phase!r}")

        if sar_ptr == 0:
            break
        sar_ptr -= 1

    measured = int(np.sum(shadow_q8[sar_code]))
    if target_bit == cfg.cap_num - 2:
        measured += int(shadow_q8[cfg.cap_num - 3])
    elif target_bit == cfg.cap_num - 1:
        measured += int(shadow_q8[cfg.cap_num - 2])
        measured += int(shadow_q8[cfg.cap_num - 3])
    return sar_code, measured


def run_rtl_equiv_calibration(
    physical_q8: np.ndarray,
    cfg: ValidationConfig,
    chip_id: int,
) -> Tuple[np.ndarray, List[Dict[str, object]]]:
    """Run a Python mirror of `sar_calib_ctrl_serial.sv`."""

    rng = stable_rng(cfg, 200, chip_id)
    shadow = np.zeros(cfg.cap_num, dtype=np.int64)
    for bit in range(cfg.max_calib_bit + 1):
        shadow[bit] = cfg.ref_weight_lsb_q8 << bit

    trace: List[Dict[str, object]] = []
    avg_shift = int(math.log2(cfg.avg_loops))
    if 1 << avg_shift != cfg.avg_loops:
        raise ValueError("avg_loops must be a power of two")

    for target in range(cfg.max_calib_bit + 1, cfg.cap_num):
        accumulator = 0
        phase_records = []
        for _ in range(cfg.avg_loops):
            p_code, meas_p = rtl_phase_search(target, "P", shadow, physical_q8, cfg, rng)
            n_code, meas_n = rtl_phase_search(target, "N", shadow, physical_q8, cfg, rng)
            accumulator += meas_p + meas_n
            phase_records.append(
                {
                    "p_code_hex": int(bits_to_word(p_code)),
                    "n_code_hex": int(bits_to_word(n_code)),
                    "meas_p_q8": int(meas_p),
                    "meas_n_q8": int(meas_n),
                }
            )

        result_q8 = int((accumulator + (1 << avg_shift)) >> (avg_shift + 1))
        shadow[target] = result_q8
        trace.append(
            {
                "target_bit": target,
                "result_q8": result_q8,
                "result_lsb": result_q8 / float(1 << cfg.frac_bits),
                "physical_lsb": float(physical_q8[target] / float(1 << cfg.frac_bits)),
                "accumulator": int(accumulator),
                "phase_sample_count": len(phase_records),
                "first_phase": phase_records[0],
                "last_phase": phase_records[-1],
            }
        )
    return shadow, trace


def bits_to_word(bits: Sequence[bool]) -> int:
    word = 0
    for index, value in enumerate(bits):
        if value:
            word |= 1 << index
    return word


def choose_decision_stream(target_codes: np.ndarray, physical_q8: np.ndarray, cfg: ValidationConfig) -> np.ndarray:
    """Generate one signed SAR-like physical decision stream.

    The same decision stream is later decoded by nominal, calibrated, and oracle
    weights. This isolates the digital-weight effect from any change in analog
    conversion decisions.
    """

    target_sum_q8 = np.rint(target_codes * 2.0 * (1 << cfg.frac_bits)).astype(np.int64)
    acc = np.zeros_like(target_sum_q8, dtype=np.int64)
    bits = np.zeros((len(target_codes), cfg.cap_num), dtype=np.int8)
    weights = np.rint(physical_q8).astype(np.int64)
    for bit in range(cfg.cap_num - 1, -1, -1):
        choose_plus = target_sum_q8 >= acc
        bits[:, bit] = choose_plus.astype(np.int8)
        acc += np.where(choose_plus, weights[bit], -weights[bit])
    return bits


def rtl_reconstruct_codes(
    bits: np.ndarray,
    weights_q8: np.ndarray,
    cfg: ValidationConfig,
    residue_q8: int = 0,
) -> Tuple[np.ndarray, float]:
    sign = bits.astype(np.int64) * 2 - 1
    weighted_sum = sign @ np.rint(weights_q8).astype(np.int64)
    normalized = (weighted_sum >> 1) + int(residue_q8)
    rounded = normalized + (1 << (cfg.frac_bits - 1))
    shifted = rounded >> cfg.frac_bits
    min_code = -(1 << (cfg.output_bits - 1))
    max_code = (1 << (cfg.output_bits - 1)) - 1
    saturated = (shifted < min_code) | (shifted > max_code)
    return np.clip(shifted, min_code, max_code).astype(np.int32), float(np.mean(saturated))


def coherent_sine(cfg: ValidationConfig) -> Tuple[np.ndarray, float, int]:
    k = int(round(cfg.fin_target_hz / cfg.fs_hz * cfg.n_fft))
    k = max(1, min(k, cfg.n_fft // 2 - 1))
    if k % 2 == 0 and k + 1 < cfg.n_fft // 2:
        k += 1
    fin = cfg.fs_hz * k / cfg.n_fft
    n = np.arange(cfg.n_fft)
    target = cfg.sine_amplitude_code * np.sin(2.0 * np.pi * k * n / cfg.n_fft)
    return target, fin, k


def fold_harmonic_bin(k: int, n: int) -> int:
    folded = k % n
    return int(n - folded if folded > n // 2 else folded)


def analyze_spectrum(codes: np.ndarray, cfg: ValidationConfig, fundamental_bin: int) -> Dict[str, float]:
    samples = codes.astype(float) - float(np.mean(codes))
    power = np.abs(np.fft.rfft(samples)) ** 2
    power[0] = 0.0
    p_signal = float(power[fundamental_bin])
    harmonics = set()
    for harmonic in range(2, 9):
        folded = fold_harmonic_bin(harmonic * fundamental_bin, len(samples))
        if 0 < folded < len(power) and folded != fundamental_bin:
            harmonics.add(folded)
    p_harmonic = float(sum(power[index] for index in harmonics))
    p_sndr = float(np.sum(power) - power[fundamental_bin])
    p_snr = float(np.sum(power) - power[fundamental_bin] - p_harmonic)
    p_spur = float(
        max((power[index] for index in range(1, len(power)) if index != fundamental_bin), default=0.0)
    )
    eps = 1e-300
    sndr = 10.0 * math.log10((p_signal + eps) / (p_sndr + eps))
    snr = 10.0 * math.log10((p_signal + eps) / (p_snr + eps))
    sfdr = 10.0 * math.log10((p_signal + eps) / (p_spur + eps))
    thd = 10.0 * math.log10((p_harmonic + eps) / (p_signal + eps))
    return {
        "sndr_db": sndr,
        "snr_db": snr,
        "sfdr_db": sfdr,
        "thd_db": thd,
        "enob": (sndr - 1.76) / 6.02,
    }


def static_targets(cfg: ValidationConfig) -> np.ndarray:
    return np.linspace(
        -cfg.ramp_amplitude_code,
        cfg.ramp_amplitude_code,
        cfg.ramp_points,
        endpoint=True,
    )


def best_gain_align(reference: np.ndarray, estimate: np.ndarray) -> Tuple[np.ndarray, float]:
    denom = float(np.dot(estimate, estimate))
    if denom <= 0.0:
        return estimate.copy(), 1.0
    gain = float(np.dot(reference, estimate) / denom)
    return estimate * gain, gain


def evaluate_decoder(
    chip_id: int,
    decoder_name: str,
    physical_q8: np.ndarray,
    weights_q8: np.ndarray,
    sine_bits: np.ndarray,
    sine_bin: int,
    ramp_bits: np.ndarray,
    ramp_target: np.ndarray,
    cfg: ValidationConfig,
) -> ChipResult:
    weight_ref_lsb = physical_q8 / float(1 << cfg.frac_bits)
    weight_est_lsb = weights_q8 / float(1 << cfg.frac_bits)
    aligned_lsb, _ = best_gain_align(weight_ref_lsb, weight_est_lsb)
    weight_error = weight_est_lsb - weight_ref_lsb
    aligned_error = aligned_lsb - weight_ref_lsb

    ramp_codes, ramp_sat = rtl_reconstruct_codes(ramp_bits, weights_q8, cfg)
    sine_codes, sine_sat = rtl_reconstruct_codes(sine_bits, weights_q8, cfg)
    ramp_error = ramp_codes.astype(float) - ramp_target
    spectrum = analyze_spectrum(sine_codes, cfg, sine_bin)

    return ChipResult(
        chip_id=chip_id,
        decoder=decoder_name,
        weight_rmse_lsb=float(np.sqrt(np.mean(weight_error**2))),
        weight_rmse_gain_aligned_lsb=float(np.sqrt(np.mean(aligned_error**2))),
        weight_max_abs_gain_aligned_lsb=float(np.max(np.abs(aligned_error))),
        static_error_rms_code=float(np.sqrt(np.mean(ramp_error**2))),
        static_error_max_abs_code=float(np.max(np.abs(ramp_error))),
        static_backsteps=int(np.count_nonzero(np.diff(ramp_codes) < 0)),
        dynamic_sndr_db=spectrum["sndr_db"],
        dynamic_snr_db=spectrum["snr_db"],
        dynamic_sfdr_db=spectrum["sfdr_db"],
        dynamic_thd_db=spectrum["thd_db"],
        dynamic_enob=spectrum["enob"],
        saturation_fraction=float(max(ramp_sat, sine_sat)),
    )


def summarize(values: Iterable[float]) -> Dict[str, float]:
    data = np.asarray(list(values), dtype=float)
    return {
        "mean": float(np.mean(data)),
        "std": float(np.std(data, ddof=1)) if len(data) > 1 else 0.0,
        "min": float(np.min(data)),
        "p05": float(np.percentile(data, 5)),
        "median": float(np.percentile(data, 50)),
        "p95": float(np.percentile(data, 95)),
        "max": float(np.max(data)),
    }


def aggregate_results(results: Sequence[ChipResult]) -> Dict[str, object]:
    summary: Dict[str, object] = {}
    for decoder in sorted({result.decoder for result in results}):
        subset = [result for result in results if result.decoder == decoder]
        summary[decoder] = {
            "n_chips": len(subset),
            "weight_rmse_gain_aligned_lsb": summarize(
                item.weight_rmse_gain_aligned_lsb for item in subset
            ),
            "weight_max_abs_gain_aligned_lsb": summarize(
                item.weight_max_abs_gain_aligned_lsb for item in subset
            ),
            "static_error_rms_code": summarize(item.static_error_rms_code for item in subset),
            "static_error_max_abs_code": summarize(item.static_error_max_abs_code for item in subset),
            "static_backsteps": summarize(float(item.static_backsteps) for item in subset),
            "dynamic_sndr_db": summarize(item.dynamic_sndr_db for item in subset),
            "dynamic_sfdr_db": summarize(item.dynamic_sfdr_db for item in subset),
            "dynamic_enob": summarize(item.dynamic_enob for item in subset),
            "saturation_fraction": summarize(item.saturation_fraction for item in subset),
        }
    return summary


def write_csv(results: Sequence[ChipResult], path: Path) -> None:
    fieldnames = list(asdict(results[0]).keys())
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for result in results:
            writer.writerow(asdict(result))


def plot_summary(summary: Dict[str, object], outdir: Path) -> None:
    order = ["NOMINAL", "RTL_CAL_RAW", "RTL_CAL_GAIN_COMP", "ORACLE"]
    labels = {
        "NOMINAL": "Nominal",
        "RTL_CAL_RAW": "RTL-equivalent cal",
        "RTL_CAL_GAIN_COMP": "Cal + gain align",
        "ORACLE": "Physical oracle",
    }

    def median(decoder: str, metric: str) -> float:
        return float(summary[decoder][metric]["median"])  # type: ignore[index]

    plt.figure(figsize=(8.8, 4.8))
    x = np.arange(len(order))
    y = [median(name, "dynamic_sndr_db") for name in order]
    plt.bar(x, y, color=["#7c8794", "#2f6f9f", "#2b8a6e", "#6f5aa8"])
    plt.xticks(x, [labels[name] for name in order], rotation=12, ha="right")
    plt.ylabel("SNDR median (dB)")
    plt.title("Dynamic same-decision reconstruction")
    plt.grid(True, axis="y", alpha=0.25)
    plt.tight_layout()
    plt.savefig(outdir / "fig_dynamic_sndr_median.png", dpi=180)
    plt.close()

    plt.figure(figsize=(8.8, 4.8))
    y = [median(name, "weight_rmse_gain_aligned_lsb") for name in order]
    plt.bar(x, y, color=["#7c8794", "#2f6f9f", "#2b8a6e", "#6f5aa8"])
    plt.xticks(x, [labels[name] for name in order], rotation=12, ha="right")
    plt.ylabel("Gain-aligned weight RMSE (LSB)")
    plt.yscale("log")
    plt.title("Weight estimate error")
    plt.grid(True, axis="y", which="both", alpha=0.25)
    plt.tight_layout()
    plt.savefig(outdir / "fig_weight_rmse.png", dpi=180)
    plt.close()


def run_validation(cfg: ValidationConfig, outdir: Path, no_plots: bool = False) -> Dict[str, object]:
    outdir.mkdir(parents=True, exist_ok=True)
    nominal_q8 = ideal_weight_q8(cfg).astype(float)
    sine_target, fin, sine_bin = coherent_sine(cfg)
    ramp_target = static_targets(cfg)

    results: List[ChipResult] = []
    traces: Dict[str, object] = {}
    for chip_id in range(cfg.n_chips):
        physical_q8 = manufacture_chip_q8(cfg, chip_id)
        calibrated_q8, trace = run_rtl_equiv_calibration(physical_q8, cfg, chip_id)

        # This gain-aligned path mirrors the existing TB scoreboard convention.
        # It is reported separately because the current reconstruction RTL does
        # not contain an explicit gain-compensation register.
        gain_comp = float(physical_q8[-1] / calibrated_q8[-1]) if calibrated_q8[-1] != 0 else 1.0
        calibrated_gain_q8 = np.rint(calibrated_q8.astype(float) * gain_comp)

        sine_bits = choose_decision_stream(sine_target, physical_q8, cfg)
        ramp_bits = choose_decision_stream(ramp_target, physical_q8, cfg)
        decoders = {
            "NOMINAL": nominal_q8,
            "RTL_CAL_RAW": calibrated_q8.astype(float),
            "RTL_CAL_GAIN_COMP": calibrated_gain_q8.astype(float),
            "ORACLE": physical_q8.astype(float),
        }
        for name, weights in decoders.items():
            results.append(
                evaluate_decoder(
                    chip_id,
                    name,
                    physical_q8,
                    weights,
                    sine_bits,
                    sine_bin,
                    ramp_bits,
                    ramp_target,
                    cfg,
                )
            )
        if chip_id < 3:
            traces[f"chip_{chip_id}"] = {
                "physical_weights_lsb": (physical_q8 / float(1 << cfg.frac_bits)).tolist(),
                "calibrated_weights_lsb": (calibrated_q8 / float(1 << cfg.frac_bits)).tolist(),
                "gain_compensation_factor": gain_comp,
                "calibration_trace": trace,
            }

    summary = aggregate_results(results)
    payload = {
        "scope": "Behavioral RTL-equivalent validation; not AMS/transistor/PVT/PEX signoff.",
        "method": (
            "Same physical decision stream decoded by nominal, RTL-equivalent "
            "calibrated, gain-compensated calibrated, and physical-oracle weights."
        ),
        "source_of_truth": {
            "calibration_algorithm": "rtl/sar_calib_ctrl_serial.sv",
            "reconstruction_arithmetic": "rtl/sar_reconstruction.sv",
            "fixed_point_contract": "docs/FIXED_POINT_CONTRACT.md",
            "rtl_testbenches": [
                "Digital_process/Digital_process.srcs/sim_1/new/tb_gain_comp_check_lsb.sv",
                "Digital_process/Digital_process.srcs/sim_1/new/tb_recon_q8_split_weights.sv",
                "Digital_process/Digital_process.srcs/sim_1/new/tb_sar_recon_binary_norm.sv",
            ],
            "external_reference_role": (
                "12-bit project and ADCToolbox experience are used only for validation "
                "methodology: same-decision nominal/calibrated/oracle comparison, "
                "separate static/dynamic evidence, and clear signoff boundaries. "
                "No open-source calibration algorithm is used as the implemented "
                "foreground calibration scheme in this validation."
            ),
        },
        "config": asdict(cfg),
        "coherent_input": {"fin_hz": fin, "fft_bin": sine_bin},
        "summary": summary,
        "trace_excerpt": traces,
        "rtl_boundaries": [
            "Current RTL calibration writes one shared Q8 weight per bit, not independent P/N weights.",
            "RTL_CAL_GAIN_COMP is a diagnostic matching the existing testbench scoreboard; it is not an explicit reconstruction RTL block.",
            "The normal-conversion bit stream is generated by a signed greedy behavioral converter, not by a transistor CDAC/SAR controller.",
            "SRM residue is held at zero in this validation to isolate foreground weight calibration.",
        ],
    }
    write_csv(results, outdir / "per_chip_results.csv")
    with (outdir / "summary.json").open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
    if not no_plots:
        plot_summary(summary, outdir)
    return payload


def print_summary(payload: Dict[str, object]) -> None:
    print("=== Current calibration effectiveness validation ===")
    print(payload["scope"])
    print(payload["method"])
    summary = payload["summary"]  # type: ignore[assignment]
    for decoder in ["NOMINAL", "RTL_CAL_RAW", "RTL_CAL_GAIN_COMP", "ORACLE"]:
        item = summary[decoder]  # type: ignore[index]
        sndr = item["dynamic_sndr_db"]["median"]
        sfdr = item["dynamic_sfdr_db"]["median"]
        wrmse = item["weight_rmse_gain_aligned_lsb"]["median"]
        erms = item["static_error_rms_code"]["median"]
        sat = item["saturation_fraction"]["max"]
        print(
            f"{decoder:18s} SNDR_med={sndr:8.3f} dB "
            f"SFDR_med={sfdr:8.3f} dBc "
            f"W_RMSE_med={wrmse:9.4f} LSB "
            f"static_RMS_med={erms:9.4f} code "
            f"sat_max={sat:.6f}"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--outdir",
        type=Path,
        default=Path(__file__).resolve().parent / "outputs",
    )
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--no-plots", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    cfg = ValidationConfig()
    if args.quick:
        cfg = ValidationConfig(
            n_chips=6,
            n_fft=2048,
            ramp_points=1024,
        )
    payload = run_validation(cfg, args.outdir, no_plots=args.no_plots)
    print_summary(payload)
    print(f"Artifacts written to: {args.outdir}")


if __name__ == "__main__":
    main()

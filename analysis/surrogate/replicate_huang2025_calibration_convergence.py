"""Huang 2025 calibration-error-limited convergence surrogate.

This module evaluates a carefully bounded statistical question:

    calibration measurement noise and averaging time
        -> digital weight uncertainty
        -> quantized 16-bit SNDR/SFDR/ENOB trend

It is not an RTL golden model and is not a full-ADC reproduction.  In
particular, it does not implement the LSB-DAC switching sequence, P/N cycles,
recursive RTL state machine, SRM LUT, analog sampling noise, reference
settling, or distortion mechanisms.  The 20-entry weight vector is a
reconstruction-domain-derived proxy and is intentionally diagnosed before it
is used as a unipolar greedy SAR conversion vector.

Two domain rules prevent optimistic or unit-inconsistent conclusions:

1. Dynamic metrics are evaluated after an explicit 16-bit output quantizer.
2. The paper-referenced calibration noise values are expressed in external
   16-bit output LSBs, not in the smallest entry of the proxy weight table.

The generated results are suitable for studying averaging convergence trends.
They are not suitable for claiming paper-equivalent absolute performance or
silicon yield.
"""

from __future__ import annotations

import argparse
import csv
import json
from dataclasses import asdict, dataclass, replace
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

import matplotlib.pyplot as plt
import numpy as np

try:
    from adctoolbox import calibrate_weight_sine as adctb_calibrate_weight_sine
except ImportError:  # pragma: no cover - optional independent baseline.
    adctb_calibrate_weight_sine = None


@dataclass(frozen=True)
class SimConfig:
    """Simulation controls and expressly bounded paper-inspired assumptions."""

    fs: float = 1.0e6
    fin_train_target: float = 1.0e3
    fin_test_target: float = 20.0e3
    n_samples_train: int = 2**15
    n_samples_test: int = 2**15
    input_amplitude: float = 0.49
    input_dc: float = 0.5
    test_phase_rad: float = 0.37
    seed: int = 202503

    output_bits: int = 16
    rtl_frac_bits: int = 8
    n_total_decisions: int = 20
    n_msb_measured_by_lsb_ref: int = 14
    n_lsb_reference_bits: int = 6

    # Effective-weight mismatch proxy, not a physical capacitor mismatch law.
    effective_weight_sigma: float = 0.015

    # Paper-referenced noise anchors in external 16-bit output LSBs:
    # 111 uVrms / 80 uV and 38 uVrms / 80 uV.
    meas_noise_lsb_wo_ss_srm: float = 111.0 / 80.0
    meas_noise_lsb_w_ss_srm: float = 38.0 / 80.0

    # Approximate fixed reference-DAC uncertainty per virtual chip.
    lsb_ref_static_sigma_lsb: float = 0.39 / 3.0

    navg_values: Tuple[int, ...] = (
        1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 640, 1024
    )
    n_mc: int = 80

    # Trend markers only; these are not full-ADC acceptance specifications.
    trend_sndr_db: float = 94.0
    trend_sfdr_mean_db: float = 108.0
    trend_sfdr_p5_db: float = 100.0

    ramp_points: int = 2**17


@dataclass
class VirtualChip:
    """One paired Monte Carlo sample with fixed static errors."""

    actual_weights: np.ndarray
    nominal_weights: np.ndarray
    ref_static_error_weights: np.ndarray
    chip_id: int


@dataclass
class Capture:
    """Independent calibration and evaluation records for one virtual chip."""

    vin_train: np.ndarray
    vin_test: np.ndarray
    bits_train: np.ndarray
    bits_test: np.ndarray
    fin_train: float
    fin_test: float
    k_train: int
    k_test: int


def make_reconstruction_domain_proxy_units() -> np.ndarray:
    """Return the reviewed, MSB-first proxy weight table.

    The entries follow the project's reconstruction contract table in output
    code-LSB-like units.  They are not a physical CDAC extraction or a proven
    analog decision vector.
    """

    return np.array(
        [
            40248.69, 20124.35, 10062.17, 5031.09, 5031.09,
            2535.25, 1267.63, 633.81, 316.91, 316.91,
            268.20, 134.10, 67.05, 33.53,
            32.00, 16.00, 8.00, 4.00, 2.00, 1.00,
        ],
        dtype=float,
    )


def external_lsb_norm(cfg: SimConfig) -> float:
    """Return one normalized external output LSB."""

    return 1.0 / float(1 << cfg.output_bits)


def proxy_denominator_units(nominal_units: np.ndarray) -> float:
    """Provide a fixed proxy normalization denominator for all chips."""

    return float(np.sum(nominal_units) + 1.0)


def normalize_proxy_units(units: np.ndarray, denominator_units: float) -> np.ndarray:
    """Normalize proxy decision weights without hiding total-gain variation."""

    return np.asarray(units, dtype=float) / denominator_units


def apply_effective_weight_mismatch_proxy(
    nominal_units: np.ndarray,
    sigma: float,
    rng: np.random.Generator,
) -> np.ndarray:
    """Perturb effective weights with a simple size-related trend.

    This operation is only a source of static error for trend experiments.  A
    physical model must instead build the split/bridge CDAC and parasitics,
    perturb physical capacitances, then derive effective decision weights.
    """

    rel_sigma = sigma / np.sqrt(np.maximum(nominal_units, 1.0))
    return nominal_units * (1.0 + rel_sigma * rng.standard_normal(len(nominal_units)))


def stable_rng(cfg: SimConfig, *items: int) -> np.random.Generator:
    """Create a reproducible generator independent of Python hash seeding."""

    return np.random.default_rng(np.random.SeedSequence([cfg.seed, *map(int, items)]))


def create_virtual_chip(cfg: SimConfig, chip_id: int) -> VirtualChip:
    """Create one chip while keeping paper LSB noise in external code units."""

    nominal_units = make_reconstruction_domain_proxy_units()
    denom = proxy_denominator_units(nominal_units)
    rng = stable_rng(cfg, 200, chip_id)
    actual_units = apply_effective_weight_mismatch_proxy(
        nominal_units, cfg.effective_weight_sigma, rng
    )
    nominal_weights = normalize_proxy_units(nominal_units, denom)
    actual_weights = normalize_proxy_units(actual_units, denom)

    ref_static_error_weights = np.zeros_like(nominal_weights)
    ref_sigma = cfg.lsb_ref_static_sigma_lsb * external_lsb_norm(cfg)
    ref_static_error_weights[: cfg.n_msb_measured_by_lsb_ref] = (
        ref_sigma * rng.standard_normal(cfg.n_msb_measured_by_lsb_ref)
    )
    return VirtualChip(
        actual_weights=actual_weights,
        nominal_weights=nominal_weights,
        ref_static_error_weights=ref_static_error_weights,
        chip_id=chip_id,
    )


def coherent_frequency(fs: float, fin_target: float, n: int) -> Tuple[float, int]:
    """Return a nearby coherent odd-bin tone and its FFT bin."""

    k = int(round(fin_target / fs * n))
    k = max(1, min(k, n // 2 - 1))
    if k % 2 == 0 and k + 1 < n // 2:
        k += 1
    return fs * k / n, k


def generate_sine_input(
    fs: float,
    fin_target: float,
    n_samples: int,
    amplitude: float,
    dc: float,
    phase_rad: float = 0.0,
) -> Tuple[np.ndarray, float, int]:
    """Generate a clipped coherent unipolar input record."""

    fin, k = coherent_frequency(fs, fin_target, n_samples)
    t = np.arange(n_samples) / fs
    vin = dc + amplitude * np.sin(2.0 * np.pi * fin * t + phase_rad)
    return np.clip(vin, 0.0, 1.0), fin, k


def sar_convert(vin: np.ndarray, analog_weights: np.ndarray) -> np.ndarray:
    """Run the intentionally limited greedy unipolar proxy SAR converter."""

    bits = np.zeros((len(vin), len(analog_weights)), dtype=np.int8)
    vdac = np.zeros(len(vin), dtype=float)
    for index, weight in enumerate(analog_weights):
        trial = vdac + weight
        decision = (vin >= trial).astype(np.int8)
        bits[:, index] = decision
        vdac = np.where(decision, trial, vdac)
    return bits


def reconstruct_normalized(bits: np.ndarray, weights: np.ndarray) -> np.ndarray:
    """Return normalized reconstruction prior to external output quantization."""

    return bits.astype(float) @ np.asarray(weights, dtype=float)


def quantize_external_output(
    normalized_output: np.ndarray, cfg: SimConfig
) -> Tuple[np.ndarray, float]:
    """Apply the explicit unipolar 16-bit evaluation boundary.

    Dynamic metrics must be derived from these output codes.  Returning a
    clipping fraction makes accidental over-range models visible in reports.
    """

    max_code = (1 << cfg.output_bits) - 1
    code_real = normalized_output / external_lsb_norm(cfg)
    clipped = (code_real < 0.0) | (code_real > float(max_code))
    code = np.rint(code_real)
    code = np.clip(code, 0, max_code).astype(np.int32)
    return code, float(np.mean(clipped))


def reconstructed_output_codes(
    bits: np.ndarray, weights: np.ndarray, cfg: SimConfig
) -> Tuple[np.ndarray, float]:
    """Reconstruct and quantize codes for performance statistics."""

    return quantize_external_output(reconstruct_normalized(bits, weights), cfg)


def make_capture(cfg: SimConfig, chip: VirtualChip) -> Capture:
    """Create independent-frequency training and evaluation records."""

    vin_train, fin_train, k_train = generate_sine_input(
        cfg.fs, cfg.fin_train_target, cfg.n_samples_train,
        cfg.input_amplitude, cfg.input_dc,
    )
    vin_test, fin_test, k_test = generate_sine_input(
        cfg.fs, cfg.fin_test_target, cfg.n_samples_test,
        cfg.input_amplitude, cfg.input_dc, cfg.test_phase_rad,
    )
    return Capture(
        vin_train=vin_train,
        vin_test=vin_test,
        bits_train=sar_convert(vin_train, chip.actual_weights),
        bits_test=sar_convert(vin_test, chip.actual_weights),
        fin_train=fin_train,
        fin_test=fin_test,
        k_train=k_train,
        k_test=k_test,
    )


def generate_cumulative_measurement_noise_table(
    cfg: SimConfig, chip_id: int
) -> np.ndarray:
    """Return shared standard-noise samples used by both SS+SRM cases."""

    rng = stable_rng(cfg, 9001, chip_id)
    return rng.standard_normal(
        (cfg.n_msb_measured_by_lsb_ref, max(cfg.navg_values))
    )


def mean_noise_for_navg(noise_table: np.ndarray, navg: int) -> np.ndarray:
    """Average a cumulative prefix of the per-chip measurement record."""

    if navg < 1 or navg > noise_table.shape[1]:
        raise ValueError(f"navg={navg} is outside the generated measurement table")
    return noise_table[:, :navg].mean(axis=1)


def surrogate_calibrated_weights_from_noise_model(
    chip: VirtualChip,
    cfg: SimConfig,
    meas_noise_lsb: float,
    standard_noise_mean: np.ndarray,
    include_ref_static_error: bool = True,
) -> np.ndarray:
    """Estimate high weights with an external-LSB measurement-error model.

    This function knows the true virtual-chip weights and adds error; it does
    not discover the weights through an implemented calibration sequence.
    """

    measured_count = cfg.n_msb_measured_by_lsb_ref
    if standard_noise_mean.shape != (measured_count,):
        raise ValueError("standard_noise_mean has an incompatible shape")

    weights = chip.nominal_weights.copy()
    noise_scale = meas_noise_lsb * external_lsb_norm(cfg)
    static_error: np.ndarray | float
    static_error = (
        chip.ref_static_error_weights[:measured_count]
        if include_ref_static_error
        else 0.0
    )
    weights[:measured_count] = (
        chip.actual_weights[:measured_count]
        + static_error
        + noise_scale * standard_noise_mean
    )
    weights[:measured_count] = np.maximum(weights[:measured_count], 0.0)
    return weights


def fold_harmonic_bin(k: int, n: int) -> int:
    """Fold a harmonic into the real-FFT Nyquist interval."""

    folded = k % n
    return int(n - folded if folded > n // 2 else folded)


def analyze_spectrum(
    output_codes: np.ndarray,
    fs: float,
    fundamental_bin: int,
    n_harmonics: int = 8,
) -> Dict[str, float | np.ndarray]:
    """Extract coherent-record SNDR/SNR/SFDR/THD/ENOB from output codes."""

    samples = np.asarray(output_codes, dtype=float)
    samples = samples - np.mean(samples)
    n = len(samples)
    fft_values = np.fft.rfft(samples)
    power = np.abs(fft_values) ** 2
    power[0] = 0.0

    harmonics = set()
    for harmonic in range(2, n_harmonics + 1):
        bin_index = fold_harmonic_bin(harmonic * fundamental_bin, n)
        if 0 < bin_index < len(power) and bin_index != fundamental_bin:
            harmonics.add(bin_index)

    p_signal = float(power[fundamental_bin])
    p_harmonic = float(sum(power[index] for index in harmonics))
    p_sndr = float(np.sum(power) - power[fundamental_bin])
    p_snr = float(
        np.sum(power) - power[fundamental_bin]
        - sum(power[index] for index in harmonics)
    )
    spur_bins = [index for index in range(1, len(power)) if index != fundamental_bin]
    p_spur = float(max((power[index] for index in spur_bins), default=0.0))

    eps = 1e-300
    sndr = 10.0 * np.log10((p_signal + eps) / (p_sndr + eps))
    snr = 10.0 * np.log10((p_signal + eps) / (p_snr + eps))
    sfdr = 10.0 * np.log10((p_signal + eps) / (p_spur + eps))
    thd = 10.0 * np.log10((p_harmonic + eps) / (p_signal + eps))
    return {
        "snr_db": float(snr),
        "sndr_db": float(sndr),
        "sfdr_db": float(sfdr),
        "thd_db": float(thd),
        "enob": float((sndr - 1.76) / 6.02),
        "freqs": np.fft.rfftfreq(n, 1.0 / fs),
        "spectrum_db": 10.0 * np.log10((power + eps) / (p_signal + eps)),
    }


def rtl_q8_direct_mapping_diagnostic(
    bits_msb_first: np.ndarray, cfg: SimConfig
) -> Dict[str, float | int]:
    """Apply the RTL arithmetic to the proxy table as a diagnostic only.

    The proxy SAR bit generation has not been proven equivalent to the RTL raw
    bit semantics.  Any saturation shown here is evidence against treating the
    direct mapping as an already-closed system model.
    """

    weight_q8 = np.rint(
        make_reconstruction_domain_proxy_units() * (1 << cfg.rtl_frac_bits)
    ).astype(np.int64)
    signed_bits = 2 * bits_msb_first.astype(np.int64) - 1
    weighted_sum = signed_bits @ weight_q8
    normalized = np.right_shift(weighted_sum, 1)
    rounded = normalized + (1 << (cfg.rtl_frac_bits - 1))
    shifted = np.right_shift(rounded, cfg.rtl_frac_bits)
    min_code = -(1 << (cfg.output_bits - 1))
    max_code = (1 << (cfg.output_bits - 1)) - 1
    saturated = (shifted < min_code) | (shifted > max_code)
    clipped = np.clip(shifted, min_code, max_code)
    return {
        "rtl_direct_min_code": int(np.min(clipped)),
        "rtl_direct_max_code": int(np.max(clipped)),
        "rtl_direct_saturation_fraction": float(np.mean(saturated)),
    }


def proxy_sar_sanity_check(cfg: SimConfig) -> Dict[str, object]:
    """Diagnose proxy conversion behavior without claiming INL/DNL validity."""

    units = make_reconstruction_domain_proxy_units()
    denom = proxy_denominator_units(units)
    weights = normalize_proxy_units(units, denom)
    ramp = np.linspace(0.0, 1.0, cfg.ramp_points, endpoint=False)
    ramp += 0.5 / cfg.ramp_points
    bits = sar_convert(ramp, weights)
    normalized = reconstruct_normalized(bits, weights)
    codes, clip_fraction = quantize_external_output(normalized, cfg)
    delta = np.diff(codes)
    unique_codes = np.unique(codes)
    span = int(unique_codes[-1] - unique_codes[0] + 1)
    report: Dict[str, object] = {
        "qualification": "TREND_ONLY_NOT_ANALOG_OR_RTL_GOLDEN",
        "monotonic_external_codes": bool(np.all(delta >= 0)),
        "negative_steps": int(np.count_nonzero(delta < 0)),
        "occupied_external_codes": int(len(unique_codes)),
        "missing_codes_within_occupied_span": int(span - len(unique_codes)),
        "external_clip_fraction": clip_fraction,
        "proxy_sum_units": float(np.sum(units)),
        "proxy_span_bits_from_smallest_entry": float(np.log2(np.sum(units) / units[-1] + 1.0)),
        "proxy_smallest_entry_in_external_lsb": float(weights[-1] / external_lsb_norm(cfg)),
        "external_output_bits": cfg.output_bits,
    }
    report.update(rtl_q8_direct_mapping_diagnostic(bits, cfg))
    return report


def run_adctoolbox_sine_baseline(
    capture: Capture, cfg: SimConfig
) -> Optional[Tuple[np.ndarray, float]]:
    """Evaluate optional ADCToolbox weights after training-set affine scaling."""

    if adctb_calibrate_weight_sine is None:
        return None
    result = adctb_calibrate_weight_sine(
        capture.bits_train,
        freq=capture.fin_train / cfg.fs,
        force_search=False,
        harmonic_order=1,
        verbose=0,
    )
    weights = np.asarray(result["weight"], dtype=float)
    train_raw = reconstruct_normalized(capture.bits_train, weights)
    fit_matrix = np.column_stack((train_raw, np.ones_like(train_raw)))
    gain, offset = np.linalg.lstsq(fit_matrix, capture.vin_train, rcond=None)[0]
    test_scaled = gain * reconstruct_normalized(capture.bits_test, weights) + offset
    return quantize_external_output(test_scaled, cfg)


def distribution_row(
    case: str,
    navg: int,
    metric_list: Sequence[Dict[str, float | np.ndarray]],
    clip_fractions: Sequence[float],
) -> Dict[str, object]:
    """Reduce a case distribution to reportable scalar fields."""

    row: Dict[str, object] = {"case": case, "navg": navg}
    for field in ("sndr_db", "sfdr_db", "enob"):
        values = np.array([float(metric[field]) for metric in metric_list])
        stem = field.replace("_db", "")
        row[f"{stem}_mean"] = float(np.mean(values))
        row[f"{stem}_std"] = float(np.std(values, ddof=1))
        row[f"{stem}_min"] = float(np.min(values))
        row[f"{stem}_p1"] = float(np.percentile(values, 1))
        row[f"{stem}_p5"] = float(np.percentile(values, 5))
        row[f"{stem}_median"] = float(np.percentile(values, 50))
        row[f"{stem}_p95"] = float(np.percentile(values, 95))
    row["clip_fraction_mean"] = float(np.mean(clip_fractions))
    row["clip_fraction_max"] = float(np.max(clip_fractions))
    return row


def evaluate_weights(
    chips: Sequence[VirtualChip],
    captures: Dict[int, Capture],
    cfg: SimConfig,
    weight_provider,
) -> Tuple[List[Dict[str, float | np.ndarray]], List[float]]:
    """Evaluate one digital-weight selection rule over paired chips."""

    metrics: List[Dict[str, float | np.ndarray]] = []
    clip_fractions: List[float] = []
    for chip in chips:
        weights = weight_provider(chip)
        capture = captures[chip.chip_id]
        codes, clipped = reconstructed_output_codes(capture.bits_test, weights, cfg)
        metrics.append(analyze_spectrum(codes, cfg.fs, capture.k_test))
        clip_fractions.append(clipped)
    return metrics, clip_fractions


def paired_cumulative_sweep(cfg: SimConfig) -> List[Dict[str, object]]:
    """Run paired chips with cumulative measurement averages."""

    chips = [create_virtual_chip(cfg, chip_id) for chip_id in range(cfg.n_mc)]
    captures = {chip.chip_id: make_capture(cfg, chip) for chip in chips}
    noise_tables = {
        chip.chip_id: generate_cumulative_measurement_noise_table(cfg, chip.chip_id)
        for chip in chips
    }
    zero_noise = np.zeros(cfg.n_msb_measured_by_lsb_ref)
    rows: List[Dict[str, object]] = []

    baselines = {
        "UNCALIBRATED_NOMINAL": lambda chip: chip.nominal_weights,
        "ORACLE_ACTUAL_WEIGHT": lambda chip: chip.actual_weights,
        "STATIC_REF_FLOOR": lambda chip: surrogate_calibrated_weights_from_noise_model(
            chip, cfg, 0.0, zero_noise, include_ref_static_error=True
        ),
    }
    for name, provider in baselines.items():
        metrics, clips = evaluate_weights(chips, captures, cfg, provider)
        rows.append(distribution_row(name, 0, metrics, clips))

    dynamic_cases = {
        "W_SS_SRM": cfg.meas_noise_lsb_w_ss_srm,
        "WO_SS_SRM": cfg.meas_noise_lsb_wo_ss_srm,
    }
    for navg in cfg.navg_values:
        for name, noise_lsb in dynamic_cases.items():
            def provider(chip: VirtualChip, scale: float = noise_lsb, count: int = navg) -> np.ndarray:
                mean_noise = mean_noise_for_navg(noise_tables[chip.chip_id], count)
                return surrogate_calibrated_weights_from_noise_model(
                    chip, cfg, scale, mean_noise, include_ref_static_error=True
                )

            metrics, clips = evaluate_weights(chips, captures, cfg, provider)
            rows.append(distribution_row(name, navg, metrics, clips))
    return rows


def single_chip_spectrum(cfg: SimConfig) -> Dict[str, Dict[str, float | np.ndarray]]:
    """Generate spectrum curves for one reproducible representative chip."""

    chip = create_virtual_chip(cfg, 0)
    capture = make_capture(cfg, chip)
    noise = mean_noise_for_navg(generate_cumulative_measurement_noise_table(cfg, 0), 64)
    zero_noise = np.zeros(cfg.n_msb_measured_by_lsb_ref)
    weights = {
        "UNCALIBRATED_NOMINAL": chip.nominal_weights,
        "ORACLE_ACTUAL_WEIGHT": chip.actual_weights,
        "STATIC_REF_FLOOR": surrogate_calibrated_weights_from_noise_model(
            chip, cfg, 0.0, zero_noise
        ),
        "W_SS_SRM_NAVG64": surrogate_calibrated_weights_from_noise_model(
            chip, cfg, cfg.meas_noise_lsb_w_ss_srm, noise
        ),
    }
    output: Dict[str, Dict[str, float | np.ndarray]] = {}
    for name, digital_weights in weights.items():
        codes, clipped = reconstructed_output_codes(capture.bits_test, digital_weights, cfg)
        metric = analyze_spectrum(codes, cfg.fs, capture.k_test)
        metric["clip_fraction"] = clipped
        output[name] = metric

    optional_codes = run_adctoolbox_sine_baseline(capture, cfg)
    if optional_codes is not None:
        codes, clipped = optional_codes
        metric = analyze_spectrum(codes, cfg.fs, capture.k_test)
        metric["clip_fraction"] = clipped
        output["ADCTOOLBOX_SINE_BASELINE"] = metric
    return output


def minimum_navg(rows: Sequence[Dict[str, object]], case: str, cfg: SimConfig) -> Optional[int]:
    """Find the first trend point passing the defined descriptive markers."""

    candidates = sorted(
        (row for row in rows if row["case"] == case), key=lambda row: int(row["navg"])
    )
    for row in candidates:
        if (
            float(row["sndr_mean"]) >= cfg.trend_sndr_db
            and float(row["sfdr_mean"]) >= cfg.trend_sfdr_mean_db
            and float(row["sfdr_p5"]) >= cfg.trend_sfdr_p5_db
        ):
            return int(row["navg"])
    return None


def save_rows(rows: Sequence[Dict[str, object]], path: Path) -> None:
    """Store scalar sweep data in a stable CSV layout."""

    fieldnames = list(rows[0].keys())
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def plot_sweep(rows: Sequence[Dict[str, object]], cfg: SimConfig, outdir: Path) -> None:
    """Create convergence plots with baseline reference lines."""

    labels = {
        "UNCALIBRATED_NOMINAL": "uncalibrated nominal",
        "ORACLE_ACTUAL_WEIGHT": "oracle actual weight",
        "STATIC_REF_FLOOR": "static reference floor",
        "W_SS_SRM": "SS+SRM enabled",
        "WO_SS_SRM": "SS+SRM disabled",
    }
    dynamic = ("W_SS_SRM", "WO_SS_SRM")
    baseline = ("UNCALIBRATED_NOMINAL", "ORACLE_ACTUAL_WEIGHT", "STATIC_REF_FLOOR")
    for metric, ylabel, filename, threshold in (
        ("sndr", "Quantized 16-bit SNDR (dB)", "fig_sndr_averaging_sweep.png", cfg.trend_sndr_db),
        ("sfdr", "Quantized 16-bit SFDR (dBc)", "fig_sfdr_averaging_sweep.png", cfg.trend_sfdr_mean_db),
    ):
        plt.figure(figsize=(9.6, 5.8))
        for case in dynamic:
            subset = [row for row in rows if row["case"] == case]
            x = np.array([row["navg"] for row in subset], dtype=float)
            mean = np.array([row[f"{metric}_mean"] for row in subset], dtype=float)
            std = np.array([row[f"{metric}_std"] for row in subset], dtype=float)
            p5 = np.array([row[f"{metric}_p5"] for row in subset], dtype=float)
            plt.errorbar(x, mean, yerr=std, marker="o", capsize=3, label=f"mean/std, {labels[case]}")
            plt.plot(x, p5, linestyle="--", marker="x", linewidth=1.0, label=f"P5, {labels[case]}")
        for case in baseline:
            row = next(item for item in rows if item["case"] == case)
            plt.axhline(float(row[f"{metric}_mean"]), linestyle=":", linewidth=1.0, label=labels[case])
        plt.axhline(threshold, color="black", linestyle="-.", linewidth=1.0, label="trend marker")
        plt.xscale("log", base=2)
        plt.xlabel("Effective independent measurement count Navg")
        plt.ylabel(ylabel)
        plt.title("Calibration-error-limited convergence trend")
        plt.grid(True, which="both", alpha=0.3)
        plt.legend(fontsize=7)
        plt.tight_layout()
        plt.savefig(outdir / filename, dpi=180)
        plt.close()


def plot_single_chip(
    spectra: Dict[str, Dict[str, float | np.ndarray]], cfg: SimConfig, outdir: Path
) -> None:
    """Create a representative spectrum overlay."""

    plt.figure(figsize=(10.0, 5.8))
    for name, metric in spectra.items():
        frequency = np.asarray(metric["freqs"]) / 1.0e3
        plt.plot(frequency, metric["spectrum_db"], linewidth=1.0, label=name)
    plt.xlim(0.0, cfg.fs / 2.0 / 1.0e3)
    plt.ylim(-170.0, 5.0)
    plt.xlabel("Frequency (kHz)")
    plt.ylabel("Relative magnitude (dBc)")
    plt.title("Quantized 16-bit evaluation record")
    plt.grid(True, alpha=0.3)
    plt.legend(fontsize=8)
    plt.tight_layout()
    plt.savefig(outdir / "fig_spectrum_compare.png", dpi=180)
    plt.close()


def print_summary(
    cfg: SimConfig,
    sanity: Dict[str, object],
    rows: Sequence[Dict[str, object]],
    spectra: Dict[str, Dict[str, float | np.ndarray]],
) -> None:
    """Print the audit-relevant portion of the experiment result."""

    print("=== Model boundary ===")
    print("Trend-only statistical surrogate; not RTL golden or full ADC proof.")
    print("All FFT metrics below use explicitly quantized 16-bit output codes.")
    print("Navg is an effective independent measurement count, not RTL AVG_LOOPS.")
    print("\n=== Proxy sanity diagnostic ===")
    for key, value in sanity.items():
        print(f"{key}: {value}")
    print("\n=== Representative chip ===")
    for name, metric in spectra.items():
        print(
            f"{name:24s} SNDR={float(metric['sndr_db']):8.3f} dB "
            f"SFDR={float(metric['sfdr_db']):8.3f} dBc "
            f"ENOB={float(metric['enob']):7.3f}"
        )
    print("\n=== Paired Monte Carlo summary ===")
    for row in rows:
        if int(row["navg"]) == 0 or row["case"] in ("W_SS_SRM", "WO_SS_SRM"):
            print(
                f"{str(row['case']):22s} Navg={int(row['navg']):4d} "
                f"SNDR={float(row['sndr_mean']):7.3f} dB "
                f"SFDR={float(row['sfdr_mean']):7.3f} dBc "
                f"SFDR_P5={float(row['sfdr_p5']):7.3f} dBc"
            )
    navg_on = minimum_navg(rows, "W_SS_SRM", cfg)
    navg_off = minimum_navg(rows, "WO_SS_SRM", cfg)
    print("\n=== Descriptive trend marker ===")
    print(
        "Markers: SNDR_mean >= "
        f"{cfg.trend_sndr_db:.1f} dB, SFDR_mean >= {cfg.trend_sfdr_mean_db:.1f} dBc, "
        f"SFDR_P5 >= {cfg.trend_sfdr_p5_db:.1f} dBc"
    )
    print(f"Minimum Navg, SS+SRM enabled : {navg_on}")
    print(f"Minimum Navg, SS+SRM disabled: {navg_off}")
    if navg_on is not None and navg_off is not None:
        print(f"Disabled/enabled Navg ratio  : {navg_off / navg_on:.3f}x")
    else:
        print("Disabled/enabled Navg ratio  : unavailable in sweep range")


def parse_args() -> argparse.Namespace:
    """Parse command-line controls for full and quick validation runs."""

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--outdir",
        type=Path,
        default=Path(__file__).resolve().parent / "outputs",
        help="Directory for generated CSV, JSON, and plot artifacts.",
    )
    parser.add_argument(
        "--quick",
        action="store_true",
        help="Use a small deterministic smoke configuration.",
    )
    parser.add_argument(
        "--no-plots",
        action="store_true",
        help="Skip PNG generation while retaining numerical result files.",
    )
    return parser.parse_args()


def main() -> None:
    """Run model diagnostics, convergence sweep, and result generation."""

    args = parse_args()
    cfg = SimConfig()
    if args.quick:
        cfg = replace(
            cfg,
            n_samples_train=2**12,
            n_samples_test=2**12,
            ramp_points=2**14,
            n_mc=8,
            navg_values=(1, 8, 64, 640),
        )
    args.outdir.mkdir(parents=True, exist_ok=True)

    sanity = proxy_sar_sanity_check(cfg)
    spectra = single_chip_spectrum(cfg)
    rows = paired_cumulative_sweep(cfg)

    save_rows(rows, args.outdir / "huang2025_averaging_sweep.csv")
    with (args.outdir / "proxy_sanity_report.json").open("w", encoding="utf-8") as handle:
        json.dump({"config": asdict(cfg), "diagnostic": sanity}, handle, indent=2)
    if not args.no_plots:
        plot_sweep(rows, cfg, args.outdir)
        plot_single_chip(spectra, cfg, args.outdir)

    print(f"ADCToolbox available: {adctb_calibrate_weight_sine is not None}")
    print_summary(cfg, sanity, rows, spectra)
    print(f"\nArtifacts written to: {args.outdir}")


if __name__ == "__main__":
    main()

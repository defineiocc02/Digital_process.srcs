"""Validate foreground calibration with physical segmented-CDAC mismatch.

Main campaign
-------------
* 512 physical chips at the project-MATLAB center point (1.2% unit-cap sigma).
* Physical bit caps, bridge caps, node parasitic, and comparator input cap are
  perturbed before effective weights are solved.
* Normal conversion is noiseless; deterministic expected-count SRM residue is
  enabled so the zero-mismatch path can reach the ideal 16-bit SNDR limit.

Sensitivity campaign
--------------------
* 128 chips per unit-cap sigma point.
* Dynamic metrics only, using the same physical topology and independent test
  captures.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import asdict, replace
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple

import matplotlib.pyplot as plt
import numpy as np

# Keep the documented direct-script command usable without requiring callers
# to preconfigure PYTHONPATH. Module execution continues to use the same root.
REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from analysis.full_sar_behavioral_20260729.full_sar_model import (
    FullSarConfig,
    coherent_sine,
    full_scale_ramp,
    linearity_metrics,
    rtl_reconstruct,
    run_normal_sar_conversion,
    run_rtl_equivalent_calibration,
    spectrum_metrics,
)
from analysis.physical_cdac_mismatch_20260729.physical_cdac import (
    PhysicalCdacConfig,
    draw_physical_chip,
    nominal_weights_q8,
    redundancy_margins_lsb,
)


ROOT = Path(__file__).resolve().parent
DEFAULT_OUTDIR = ROOT / "outputs"
DECODERS = (
    "NOMINAL_SRM",
    "CAL_CURRENT_SRM",
    "CAL_ZERO_COMP_ERROR_SRM",
    "ORACLE_SRM",
)
SENSITIVITY_DECODERS = ("NOMINAL_SRM", "CAL_CURRENT_SRM", "ORACLE_SRM")
IDEAL_SNDR_MIN_DB = 97.9


def noiseless_sar_config(n_chips: int, n_fft: int = 8192) -> FullSarConfig:
    """Return a SAR configuration with no normal-conversion noise."""

    return replace(
        FullSarConfig(n_chips=n_chips, n_fft=n_fft),
        sine_amplitude_code=32766.5,
        sampling_noise_lsb=0.0,
        normal_comparator_noise_lsb=0.0,
        normal_comparator_offset_lsb=0.0,
        reference_noise_rms_fraction=0.0,
        dac_settling_error_fraction=0.0,
        srm_comparator_offset_lsb=0.0,
    )


def ideal_16bit_acceptance_gate() -> Dict[str, float | bool]:
    """Prove that the noiseless harness reaches the ideal 16-bit SNDR.

    The direct quantizer checks the spectrum-analysis path. The segmented-CDAC
    path then checks nominal physical conversion, the 22-decision expected-count
    SRM LUT, and RTL-equivalent Q8 reconstruction together. A no-SRM diagnostic
    is retained to expose the approximately 3 dB residue penalty.
    """

    cfg = noiseless_sar_config(n_chips=1, n_fft=131072)
    sine, _, _ = coherent_sine(cfg, chip_id=0)
    direct_codes = np.clip(
        np.floor(sine + 0.5),
        -(1 << (cfg.output_bits - 1)),
        (1 << (cfg.output_bits - 1)) - 1,
    ).astype(np.int32)
    direct_sndr = spectrum_metrics(direct_codes, cfg)["sndr_db"]

    nominal_q8 = nominal_weights_q8(
        PhysicalCdacConfig(
            unit_cap_sigma_pct=0.0,
            node_parasitic_sigma_pct=0.0,
            comparator_input_sigma_pct=0.0,
        )
    )
    conversion = run_normal_sar_conversion(
        sine,
        nominal_q8,
        cfg,
        chip_id=0,
        stream_id=8001,
        include_random_noise=False,
        stochastic_srm=False,
    )
    no_srm_codes, _ = rtl_reconstruct(
        conversion.raw_bits, nominal_q8, cfg, residue_q8=0
    )
    srm_codes, _ = rtl_reconstruct(
        conversion.raw_bits,
        nominal_q8,
        cfg,
        residue_q8=conversion.srm_residue_q8,
    )
    no_srm_sndr = spectrum_metrics(no_srm_codes, cfg)["sndr_db"]
    srm_sndr = spectrum_metrics(srm_codes, cfg)["sndr_db"]
    stochastic_conversion = run_normal_sar_conversion(
        sine,
        nominal_q8,
        cfg,
        chip_id=0,
        stream_id=8002,
        include_random_noise=False,
        stochastic_srm=True,
    )
    stochastic_codes, _ = rtl_reconstruct(
        stochastic_conversion.raw_bits,
        nominal_q8,
        cfg,
        residue_q8=stochastic_conversion.srm_residue_q8,
    )
    stochastic_sndr = spectrum_metrics(stochastic_codes, cfg)["sndr_db"]

    passed = bool(direct_sndr >= IDEAL_SNDR_MIN_DB and srm_sndr >= IDEAL_SNDR_MIN_DB)
    if not passed:
        raise RuntimeError(
            "Ideal 16-bit acceptance gate failed: "
            f"direct={direct_sndr:.3f} dB, segmented-CDAC+SRM={srm_sndr:.3f} dB"
        )
    return {
        "threshold_db": IDEAL_SNDR_MIN_DB,
        "direct_quantizer_sndr_db": float(direct_sndr),
        "segmented_cdac_no_srm_sndr_db": float(no_srm_sndr),
        "segmented_cdac_deterministic_srm_sndr_db": float(srm_sndr),
        "rtl_22_decision_stochastic_srm_sndr_db": float(stochastic_sndr),
        "passed": passed,
    }


def _affine_error(reference: np.ndarray, estimate: np.ndarray) -> Tuple[float, float, float]:
    ref = np.asarray(reference, dtype=float)
    est = np.asarray(estimate, dtype=float)
    design = np.column_stack((est, np.ones_like(est)))
    gain, offset = np.linalg.lstsq(design, ref, rcond=None)[0]
    aligned = gain * est + offset - ref
    return (
        float(np.sqrt(np.mean(aligned**2))),
        float(np.max(np.abs(aligned))),
        float(gain),
    )


def _weight_error(reference_q8: np.ndarray, estimate_q8: np.ndarray, frac_bits: int) -> Tuple[float, float]:
    reference = np.asarray(reference_q8, dtype=float)
    estimate = np.asarray(estimate_q8, dtype=float)
    denominator = float(np.dot(estimate, estimate))
    gain = float(np.dot(reference, estimate) / denominator) if denominator > 0.0 else 1.0
    error_lsb = (gain * estimate - reference) / float(1 << frac_bits)
    return float(np.sqrt(np.mean(error_lsb**2))), float(np.max(np.abs(error_lsb)))


def _physical_row(chip, physical_cfg: PhysicalCdacConfig) -> Dict[str, object]:
    margins = redundancy_margins_lsb(chip.weights_q8, physical_cfg.frac_bits)
    return {
        "chip_id": chip.chip_id,
        "unit_cap_sigma_pct": physical_cfg.unit_cap_sigma_pct,
        "cap_rel_error_rms_pct": float(np.sqrt(np.mean(chip.cap_rel_error**2)) * 100.0),
        "cap_rel_error_max_abs_pct": float(np.max(np.abs(chip.cap_rel_error)) * 100.0),
        "bridge_rel_error_rms_pct": float(np.sqrt(np.mean(chip.bridge_rel_error**2)) * 100.0),
        "effective_weight_rel_error_rms_pct": float(
            np.sqrt(np.mean(chip.effective_weight_rel_error**2)) * 100.0
        ),
        "effective_weight_rel_error_max_abs_pct": float(
            np.max(np.abs(chip.effective_weight_rel_error)) * 100.0
        ),
        "node_parasitic_ff": chip.node_parasitic_ff,
        "comparator_input_ff": chip.comparator_input_ff,
        "critical_redundancy_margin_min_lsb": float(np.min(margins[6:])),
    }


def evaluate_main_chip(
    chip_id: int,
    sar_cfg: FullSarConfig,
    physical_cfg: PhysicalCdacConfig,
) -> Tuple[List[Dict[str, object]], Dict[str, object]]:
    """Run one full dynamic/static mismatch-only chip."""

    chip = draw_physical_chip(physical_cfg, chip_id)
    physical_q8 = chip.weights_q8
    nominal_q8 = nominal_weights_q8(physical_cfg)
    calibrated_current, _ = run_rtl_equivalent_calibration(physical_q8, sar_cfg, chip_id)
    ideal_measurement_cfg = replace(
        sar_cfg,
        calibration_comparator_offset_lsb=0.0,
        calibration_comparator_noise_lsb=0.0,
    )
    calibrated_noiseless, _ = run_rtl_equivalent_calibration(
        physical_q8,
        ideal_measurement_cfg,
        chip_id,
    )
    weights = {
        "NOMINAL_SRM": nominal_q8,
        "CAL_CURRENT_SRM": calibrated_current,
        "CAL_ZERO_COMP_ERROR_SRM": calibrated_noiseless,
        "ORACLE_SRM": physical_q8,
    }

    sine, _, _ = coherent_sine(sar_cfg, chip_id)
    ramp = full_scale_ramp(sar_cfg)
    sine_conversion = run_normal_sar_conversion(
        sine,
        physical_q8,
        sar_cfg,
        chip_id,
        stream_id=8101,
        include_random_noise=False,
        stochastic_srm=True,
    )
    ramp_conversion = run_normal_sar_conversion(
        ramp,
        physical_q8,
        sar_cfg,
        chip_id,
        stream_id=8102,
        include_random_noise=False,
        stochastic_srm=False,
    )

    sine_codes: Dict[str, np.ndarray] = {}
    ramp_codes: Dict[str, np.ndarray] = {}
    saturation: Dict[str, float] = {}
    for name, decoder_weights in weights.items():
        sine_codes[name], sine_sat = rtl_reconstruct(
            sine_conversion.raw_bits,
            decoder_weights,
            sar_cfg,
            residue_q8=sine_conversion.srm_residue_q8,
        )
        ramp_codes[name], ramp_sat = rtl_reconstruct(
            ramp_conversion.raw_bits,
            decoder_weights,
            sar_cfg,
            residue_q8=ramp_conversion.srm_residue_q8,
        )
        saturation[name] = max(sine_sat, ramp_sat)

    rows: List[Dict[str, object]] = []
    for name in DECODERS:
        dynamic = spectrum_metrics(sine_codes[name], sar_cfg)
        static = linearity_metrics(ramp_codes[name], sar_cfg)
        code_rmse, code_max, code_gain = _affine_error(
            ramp_codes["ORACLE_SRM"], ramp_codes[name]
        )
        weight_rmse, weight_max = _weight_error(physical_q8, weights[name], sar_cfg.frac_bits)
        rows.append(
            {
                "chip_id": chip_id,
                "decoder": name,
                "sndr_db": dynamic["sndr_db"],
                "snr_db": dynamic["snr_db"],
                "sfdr_db": dynamic["sfdr_db"],
                "thd_db": dynamic["thd_db"],
                "enob": dynamic["enob"],
                "dnl_min_lsb": static["dnl_min_lsb"],
                "dnl_max_lsb": static["dnl_max_lsb"],
                "inl_min_lsb": static["inl_min_lsb"],
                "inl_max_lsb": static["inl_max_lsb"],
                "missing_codes": static["missing_codes"],
                "saturation_fraction": saturation[name],
                "code_rmse_to_oracle_affine_lsb": code_rmse,
                "code_max_to_oracle_affine_lsb": code_max,
                "code_gain_to_oracle": code_gain,
                "weight_rmse_gain_aligned_lsb": weight_rmse,
                "weight_max_gain_aligned_lsb": weight_max,
            }
        )
    return rows, _physical_row(chip, physical_cfg)


def evaluate_sensitivity_chip(
    sigma_pct: float,
    chip_id: int,
    sar_cfg: FullSarConfig,
    physical_cfg: PhysicalCdacConfig,
) -> List[Dict[str, object]]:
    """Run dynamic-only evaluation for one unit-cap sigma point."""

    local_physical_cfg = replace(physical_cfg, unit_cap_sigma_pct=float(sigma_pct))
    chip = draw_physical_chip(local_physical_cfg, chip_id)
    physical_q8 = chip.weights_q8
    nominal_q8 = nominal_weights_q8(local_physical_cfg)
    calibrated, _ = run_rtl_equivalent_calibration(physical_q8, sar_cfg, chip_id)
    weights = {
        "NOMINAL_SRM": nominal_q8,
        "CAL_CURRENT_SRM": calibrated,
        "ORACLE_SRM": physical_q8,
    }
    sine, _, _ = coherent_sine(sar_cfg, chip_id)
    conversion = run_normal_sar_conversion(
        sine,
        physical_q8,
        sar_cfg,
        chip_id,
        stream_id=8201 + int(round(sigma_pct * 100)),
        include_random_noise=False,
        stochastic_srm=True,
    )
    oracle_codes, _ = rtl_reconstruct(
        conversion.raw_bits,
        physical_q8,
        sar_cfg,
        residue_q8=conversion.srm_residue_q8,
    )
    rows = []
    for name in SENSITIVITY_DECODERS:
        codes, _ = rtl_reconstruct(
            conversion.raw_bits,
            weights[name],
            sar_cfg,
            residue_q8=conversion.srm_residue_q8,
        )
        dynamic = spectrum_metrics(codes, sar_cfg)
        code_rmse, _, _ = _affine_error(oracle_codes, codes)
        weight_rmse, _ = _weight_error(physical_q8, weights[name], sar_cfg.frac_bits)
        rows.append(
            {
                "unit_cap_sigma_pct": float(sigma_pct),
                "chip_id": chip_id,
                "decoder": name,
                "sndr_db": dynamic["sndr_db"],
                "sfdr_db": dynamic["sfdr_db"],
                "enob": dynamic["enob"],
                "code_rmse_to_oracle_affine_lsb": code_rmse,
                "weight_rmse_gain_aligned_lsb": weight_rmse,
            }
        )
    return rows


def summarize(values: Iterable[float]) -> Dict[str, float]:
    data = np.asarray(list(values), dtype=float)
    return {
        "mean": float(np.mean(data)),
        "std": float(np.std(data, ddof=1)) if data.size > 1 else 0.0,
        "min": float(np.min(data)),
        "p01": float(np.percentile(data, 1)),
        "p05": float(np.percentile(data, 5)),
        "median": float(np.percentile(data, 50)),
        "p95": float(np.percentile(data, 95)),
        "p99": float(np.percentile(data, 99)),
        "max": float(np.max(data)),
    }


def aggregate_by_decoder(rows: Sequence[Dict[str, object]], decoders: Sequence[str]) -> Dict[str, object]:
    metric_names = [key for key in rows[0] if key not in {"chip_id", "decoder", "unit_cap_sigma_pct"}]
    return {
        decoder: {
            metric: summarize(float(row[metric]) for row in rows if row["decoder"] == decoder)
            for metric in metric_names
        }
        for decoder in decoders
    }


def aggregate_sensitivity(rows: Sequence[Dict[str, object]]) -> List[Dict[str, object]]:
    output: List[Dict[str, object]] = []
    sigma_values = sorted({float(row["unit_cap_sigma_pct"]) for row in rows})
    for sigma in sigma_values:
        for decoder in SENSITIVITY_DECODERS:
            selected = [
                row for row in rows
                if float(row["unit_cap_sigma_pct"]) == sigma and row["decoder"] == decoder
            ]
            for metric in ("sndr_db", "sfdr_db", "enob", "code_rmse_to_oracle_affine_lsb", "weight_rmse_gain_aligned_lsb"):
                stats = summarize(float(row[metric]) for row in selected)
                output.append(
                    {
                        "unit_cap_sigma_pct": sigma,
                        "decoder": decoder,
                        "metric": metric,
                        **stats,
                    }
                )
    return output


def write_csv(rows: Sequence[Dict[str, object]], path: Path) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def plot_main(summary: Dict[str, object], outdir: Path) -> None:
    labels = ["Nominal+SRM", "Current cal+SRM", "Zero-error cal+SRM", "Oracle+SRM"]
    colors = ["#737373", "#147d92", "#299c59", "#6d5aa8"]
    fig, axes = plt.subplots(1, 3, figsize=(12.0, 4.2))
    definitions = (
        ("sndr_db", "Noiseless SNDR", "dB", False),
        ("weight_rmse_gain_aligned_lsb", "Weight error", "LSB rms", True),
        ("code_rmse_to_oracle_affine_lsb", "Code error to oracle", "LSB rms", True),
    )
    for axis, (metric, title, ylabel, logarithmic) in zip(axes, definitions):
        median = np.array([float(summary[name][metric]["median"]) for name in DECODERS])
        p05 = np.array([float(summary[name][metric]["p05"]) for name in DECODERS])
        p95 = np.array([float(summary[name][metric]["p95"]) for name in DECODERS])
        display = np.maximum(median, 1e-4)
        bars = axis.bar(labels, display, color=colors, width=0.66)
        axis.errorbar(
            labels,
            display,
            yerr=np.vstack((display - np.maximum(p05, 1e-4), np.maximum(p95, display) - display)),
            fmt="none",
            color="black",
            capsize=3,
        )
        if logarithmic:
            axis.set_yscale("log")
        axis.bar_label(bars, labels=[f"{value:.3g}" if value > 0.0 else "0" for value in median], padding=3, fontsize=8)
        axis.set_title(title)
        axis.set_ylabel(ylabel)
        axis.grid(axis="y", alpha=0.25)
        axis.tick_params(axis="x", rotation=22)
    fig.suptitle("Physical segmented-CDAC mismatch, 512 chips, noiseless conversion")
    fig.tight_layout()
    fig.savefig(outdir / "fig_physical_mismatch_summary.png", dpi=180)
    fig.savefig(outdir / "fig_physical_mismatch_summary.pdf")
    plt.close(fig)


def plot_sensitivity(summary_rows: Sequence[Dict[str, object]], outdir: Path) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(10.0, 4.2))
    styles = {
        "NOMINAL_SRM": ("Nominal+SRM", "#737373", "--"),
        "CAL_CURRENT_SRM": ("Current cal+SRM", "#147d92", "-"),
        "ORACLE_SRM": ("Oracle+SRM", "#6d5aa8", ":"),
    }
    for axis, metric, ylabel in (
        (axes[0], "sndr_db", "SNDR median (dB)"),
        (axes[1], "weight_rmse_gain_aligned_lsb", "Weight RMSE median (LSB)"),
    ):
        for decoder, (label, color, line_style) in styles.items():
            selected = sorted(
                [row for row in summary_rows if row["decoder"] == decoder and row["metric"] == metric],
                key=lambda row: float(row["unit_cap_sigma_pct"]),
            )
            x = np.array([float(row["unit_cap_sigma_pct"]) for row in selected])
            y = np.array([float(row["median"]) for row in selected])
            axis.plot(x, np.maximum(y, 1e-5), marker="o", color=color, linestyle=line_style, label=label)
        if metric.startswith("weight"):
            axis.set_yscale("log")
        axis.axvline(1.2, color="#b34a3c", linewidth=1.0, linestyle="-.", label="MATLAB center" if metric == "sndr_db" else None)
        axis.set_xlabel("Unit-cap relative sigma (%)")
        axis.set_ylabel(ylabel)
        axis.grid(True, alpha=0.3)
        axis.legend(fontsize=8)
    fig.suptitle("Physical unit-cap mismatch sensitivity, 128 chips per point")
    fig.tight_layout()
    fig.savefig(outdir / "fig_unit_cap_sigma_sensitivity.png", dpi=180)
    fig.savefig(outdir / "fig_unit_cap_sigma_sensitivity.pdf")
    plt.close(fig)


def run_campaign(
    sar_cfg: FullSarConfig,
    physical_cfg: PhysicalCdacConfig,
    outdir: Path,
    workers: int,
    sensitivity_chips: int,
    sigma_values: Sequence[float],
) -> Dict[str, object]:
    sar_cfg.validate()
    physical_cfg.validate()
    outdir.mkdir(parents=True, exist_ok=True)
    ideal_gate = ideal_16bit_acceptance_gate()

    decoder_rows: List[Dict[str, object]] = []
    physical_rows: List[Dict[str, object]] = []
    with ProcessPoolExecutor(max_workers=workers) as executor:
        futures = {
            executor.submit(evaluate_main_chip, chip_id, sar_cfg, physical_cfg): chip_id
            for chip_id in range(sar_cfg.n_chips)
        }
        for completed, future in enumerate(as_completed(futures), start=1):
            rows, physical = future.result()
            decoder_rows.extend(rows)
            physical_rows.append(physical)
            if completed % 16 == 0 or completed == sar_cfg.n_chips:
                print(f"Main campaign {completed}/{sar_cfg.n_chips}", flush=True)

    decoder_rows.sort(key=lambda row: (int(row["chip_id"]), DECODERS.index(str(row["decoder"]))))
    physical_rows.sort(key=lambda row: int(row["chip_id"]))
    main_summary = aggregate_by_decoder(decoder_rows, DECODERS)
    physical_summary = {
        metric: summarize(float(row[metric]) for row in physical_rows)
        for metric in physical_rows[0]
        if metric not in {"chip_id"}
    }

    sensitivity_cfg = noiseless_sar_config(sensitivity_chips, n_fft=4096)
    sensitivity_rows: List[Dict[str, object]] = []
    jobs = [(sigma, chip_id) for sigma in sigma_values for chip_id in range(sensitivity_chips)]
    with ProcessPoolExecutor(max_workers=workers) as executor:
        futures = {
            executor.submit(
                evaluate_sensitivity_chip,
                sigma,
                chip_id,
                sensitivity_cfg,
                physical_cfg,
            ): (sigma, chip_id)
            for sigma, chip_id in jobs
        }
        for completed, future in enumerate(as_completed(futures), start=1):
            sensitivity_rows.extend(future.result())
            if completed % 64 == 0 or completed == len(jobs):
                print(f"Sensitivity campaign {completed}/{len(jobs)}", flush=True)

    sensitivity_rows.sort(
        key=lambda row: (
            float(row["unit_cap_sigma_pct"]),
            int(row["chip_id"]),
            SENSITIVITY_DECODERS.index(str(row["decoder"])),
        )
    )
    sensitivity_summary = aggregate_sensitivity(sensitivity_rows)

    write_csv(decoder_rows, outdir / "per_chip_decoder_metrics.csv")
    write_csv(physical_rows, outdir / "per_chip_physical_metrics.csv")
    write_csv(sensitivity_rows, outdir / "per_chip_sensitivity_metrics.csv")
    write_csv(sensitivity_summary, outdir / "sensitivity_summary.csv")
    plot_main(main_summary, outdir)
    plot_sensitivity(sensitivity_summary, outdir)

    payload = {
        "status": "complete",
        "scope": (
            "Physical 6+4+5+5 segmented-CDAC mismatch is drawn before effective-weight matrix solving; "
            "normal conversion noise is disabled, while the RTL-realistic 22-decision stochastic SRM path is enabled for dynamic metrics. "
            "Static ramp metrics retain deterministic expected-count SRM to avoid random empty-bin artifacts."
        ),
        "evidence_boundary": (
            "The 1.2% unit-cap sigma and 2% parasitic assumptions come from the archived project MATLAB model, "
            "not a foundry PDK mismatch card. Split-sampling/VCM/AZ/flash timing remains outside this experiment."
        ),
        "sar_config": asdict(sar_cfg),
        "physical_cdac_config": asdict(physical_cfg),
        "ideal_16bit_acceptance_gate": ideal_gate,
        "main_completed_chips": sar_cfg.n_chips,
        "sensitivity_chips_per_sigma": sensitivity_chips,
        "sensitivity_sigma_pct": list(map(float, sigma_values)),
        "main_summary": main_summary,
        "physical_summary": physical_summary,
        "sensitivity_summary": sensitivity_summary,
    }
    (outdir / "summary.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return payload


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chips", type=int, default=512)
    parser.add_argument("--sensitivity-chips", type=int, default=128)
    parser.add_argument("--workers", type=int, default=max(1, min(8, (os.cpu_count() or 2) // 2)))
    parser.add_argument("--outdir", type=Path, default=DEFAULT_OUTDIR)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    sar_cfg = noiseless_sar_config(args.chips)
    physical_cfg = PhysicalCdacConfig()
    sigma_values = (0.5, 1.0, 1.2, 1.5, 2.0, 3.0)
    payload = run_campaign(
        sar_cfg,
        physical_cfg,
        args.outdir,
        max(1, args.workers),
        args.sensitivity_chips,
        sigma_values,
    )
    print("\nMain 1.2% unit-cap sigma medians")
    gate = payload["ideal_16bit_acceptance_gate"]
    print(
        "Ideal gate: "
        f"direct={gate['direct_quantizer_sndr_db']:.3f} dB, "
        f"segmented-CDAC+SRM={gate['segmented_cdac_deterministic_srm_sndr_db']:.3f} dB, "
        f"RTL-22 stochastic={gate['rtl_22_decision_stochastic_srm_sndr_db']:.3f} dB, "
        f"pass={gate['passed']}"
    )
    for decoder in DECODERS:
        metrics = payload["main_summary"][decoder]
        print(
            f"{decoder:20s} SNDR={metrics['sndr_db']['median']:.3f} dB, "
            f"weight_RMSE={metrics['weight_rmse_gain_aligned_lsb']['median']:.4f} LSB, "
            f"code_RMSE={metrics['code_rmse_to_oracle_affine_lsb']['median']:.4f} LSB"
        )
    print(f"Artifacts: {args.outdir.resolve()}")


if __name__ == "__main__":
    main()

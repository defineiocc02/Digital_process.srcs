"""Run the independent physical-CDAC calibration revalidation campaign.

This v3 runner separates four effects that the first campaign mixed together:

1. ideal 16-bit arithmetic closure versus finite-sample stochastic SRM noise;
2. full-scale gain/saturation stress versus backed-off relative-linearity tests;
3. current RTL calibration versus analysis-only scalar gain guards that do not
   use oracle physical weights;
4. exact physical residue, deterministic SRM quantization, and stochastic
   22-decision SRM estimation.

All dynamic captures disable ordinary conversion noise but retain the current
22-decision stochastic SRM. Static ramp metrics use deterministic expected-count
SRM to avoid random empty-bin artifacts.
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
from scipy.special import ndtr

plt.rcParams.update(
    {
        "pdf.fonttype": 42,
        "ps.fonttype": 42,
        "font.family": "cmr10",
        "mathtext.fontset": "cm",
        "axes.formatter.use_mathtext": True,
    }
)

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from analysis.full_sar_behavioral_20260729.full_sar_model import (
    SRM_LUT_Q8,
    FullSarConfig,
    coherent_sine,
    full_scale_ramp,
    linearity_metrics,
    rtl_reconstruct,
    run_normal_sar_conversion,
    run_rtl_equivalent_calibration,
    spectrum_metrics,
    stable_rng,
)
from analysis.physical_cdac_mismatch_20260729.physical_cdac import (
    PhysicalCdacConfig,
    draw_physical_chip,
    nominal_weights_q8,
    redundancy_margins_lsb,
)

ROOT = Path(__file__).resolve().parent
DEFAULT_OUTDIR = ROOT / "outputs_revalidation"
FULL_SCALE_AMPLITUDE = 32766.5
BACKOFF_AMPLITUDE = 26868.94
DECODERS = (
    "NOMINAL_SRM",
    "CAL_CURRENT_SRM",
    "CAL_SUM_NORM_SRM",
    "CAL_HEADROOM_GUARD_SRM",
    "CAL_ZERO_COMP_ERROR_SRM",
    "ORACLE_SRM",
)
SWEEP_DECODERS = (
    "NOMINAL_SRM",
    "CAL_CURRENT_SRM",
    "CAL_SUM_NORM_SRM",
    "CAL_HEADROOM_GUARD_SRM",
    "ORACLE_SRM",
)
IDEAL_SNDR_MIN_DB = 97.9


def noiseless_config(
    n_chips: int,
    n_fft: int = 8192,
    amplitude_code: float = FULL_SCALE_AMPLITUDE,
) -> FullSarConfig:
    """Return the zero-ordinary-noise configuration used in this campaign."""

    return replace(
        FullSarConfig(n_chips=n_chips, n_fft=n_fft),
        sine_amplitude_code=amplitude_code,
        sampling_noise_lsb=0.0,
        normal_comparator_noise_lsb=0.0,
        normal_comparator_offset_lsb=0.0,
        reference_noise_rms_fraction=0.0,
        dac_settling_error_fraction=0.0,
        srm_comparator_offset_lsb=0.0,
    )


def sum_normalized_weights(
    calibrated_q8: np.ndarray,
    nominal_q8: np.ndarray,
) -> Tuple[np.ndarray, float]:
    """Apply one non-oracle scalar gain so calibrated total weight is nominal.

    This is an analysis candidate, not current RTL. It uses only the known
    nominal total and the digitally available calibrated total.
    """

    calibrated = np.asarray(calibrated_q8, dtype=float)
    nominal = np.asarray(nominal_q8, dtype=float)
    denominator = float(np.sum(calibrated))
    if denominator <= 0.0:
        raise ValueError("calibrated weight sum must be positive")
    scale = float(np.sum(nominal) / denominator)
    return calibrated * scale, scale


def headroom_guarded_weights(
    calibrated_q8: np.ndarray,
    nominal_q8: np.ndarray,
) -> Tuple[np.ndarray, float]:
    """Apply a one-sided non-oracle gain guard for full-scale headroom.

    The calibrated sum is reduced when it exceeds the nominal sum, but it is
    never increased. A global gain increase cannot improve SNDR and can create
    rail clipping, so this candidate avoids the failure mode observed with
    symmetric sum normalization. This is an analysis candidate, not current
    RTL.
    """

    normalized, scale = sum_normalized_weights(calibrated_q8, nominal_q8)
    guarded_scale = min(1.0, scale)
    if guarded_scale == scale:
        return normalized, guarded_scale
    return np.asarray(calibrated_q8, dtype=float).copy(), guarded_scale


def decoder_weight_set(
    physical_q8: np.ndarray,
    nominal_q8: np.ndarray,
    cfg: FullSarConfig,
    chip_id: int,
) -> Tuple[Dict[str, np.ndarray], Dict[str, float]]:
    calibrated, _ = run_rtl_equivalent_calibration(physical_q8, cfg, chip_id)
    zero_error_cfg = replace(
        cfg,
        calibration_comparator_offset_lsb=0.0,
        calibration_comparator_noise_lsb=0.0,
    )
    calibrated_zero_error, _ = run_rtl_equivalent_calibration(
        physical_q8, zero_error_cfg, chip_id
    )
    normalized, scale = sum_normalized_weights(calibrated, nominal_q8)
    guarded, guarded_scale = headroom_guarded_weights(calibrated, nominal_q8)
    return (
        {
            "NOMINAL_SRM": nominal_q8,
            "CAL_CURRENT_SRM": calibrated,
            "CAL_SUM_NORM_SRM": normalized,
            "CAL_HEADROOM_GUARD_SRM": guarded,
            "CAL_ZERO_COMP_ERROR_SRM": calibrated_zero_error,
            "ORACLE_SRM": physical_q8,
        },
        {
            "CAL_SUM_NORM_SRM": scale,
            "CAL_HEADROOM_GUARD_SRM": guarded_scale,
        },
    )


def affine_error(
    reference: np.ndarray,
    estimate: np.ndarray,
) -> Tuple[float, float, float, float]:
    ref = np.asarray(reference, dtype=float)
    est = np.asarray(estimate, dtype=float)
    design = np.column_stack((est, np.ones_like(est)))
    gain, offset = np.linalg.lstsq(design, ref, rcond=None)[0]
    error = gain * est + offset - ref
    return (
        float(np.sqrt(np.mean(error**2))),
        float(np.max(np.abs(error))),
        float(gain),
        float(offset),
    )


def weight_error(
    reference_q8: np.ndarray,
    estimate_q8: np.ndarray,
    frac_bits: int,
) -> Tuple[float, float, float]:
    reference = np.asarray(reference_q8, dtype=float)
    estimate = np.asarray(estimate_q8, dtype=float)
    denominator = float(np.dot(estimate, estimate))
    gain = float(np.dot(reference, estimate) / denominator) if denominator > 0.0 else 1.0
    error_lsb = (gain * estimate - reference) / float(1 << frac_bits)
    return (
        float(np.sqrt(np.mean(error_lsb**2))),
        float(np.max(np.abs(error_lsb))),
        gain,
    )


def physical_row(chip, cfg: PhysicalCdacConfig) -> Dict[str, object]:
    margins = redundancy_margins_lsb(chip.weights_q8, cfg.frac_bits)
    return {
        "chip_id": chip.chip_id,
        "unit_cap_sigma_pct": cfg.unit_cap_sigma_pct,
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


def ideal_acceptance() -> Dict[str, object]:
    """Run direct, no-SRM, expected-SRM, and stochastic-SRM ideal baselines."""

    cfg = noiseless_config(n_chips=1, n_fft=131072)
    sine, _, _ = coherent_sine(cfg, chip_id=0)
    direct = np.clip(
        np.floor(sine + 0.5),
        -(1 << (cfg.output_bits - 1)),
        (1 << (cfg.output_bits - 1)) - 1,
    ).astype(np.int32)
    direct_metrics = spectrum_metrics(direct, cfg)

    zero_physical = PhysicalCdacConfig(
        unit_cap_sigma_pct=0.0,
        node_parasitic_sigma_pct=0.0,
        comparator_input_sigma_pct=0.0,
    )
    weights_q8 = nominal_weights_q8(zero_physical)
    conversion = run_normal_sar_conversion(
        sine,
        weights_q8,
        cfg,
        chip_id=0,
        stream_id=7001,
        include_random_noise=False,
        stochastic_srm=False,
    )
    no_srm, _ = rtl_reconstruct(conversion.raw_bits, weights_q8, cfg, 0)
    exact_residue, _ = rtl_reconstruct(
        conversion.raw_bits,
        weights_q8,
        cfg,
        np.rint(conversion.physical_residue_q8).astype(np.int64),
    )
    expected_srm, _ = rtl_reconstruct(
        conversion.raw_bits, weights_q8, cfg, conversion.srm_residue_q8
    )
    no_srm_metrics = spectrum_metrics(no_srm, cfg)
    exact_residue_metrics = spectrum_metrics(exact_residue, cfg)
    expected_metrics = spectrum_metrics(expected_srm, cfg)

    probability = ndtr(
        conversion.physical_residue_q8
        / (cfg.srm_comparator_noise_lsb * float(1 << cfg.frac_bits))
    )
    stochastic_sndr = []
    for trial in range(16):
        rng = stable_rng(cfg, 7002, trial)
        count = rng.binomial(cfg.srm_decisions, probability)
        codes, _ = rtl_reconstruct(
            conversion.raw_bits,
            weights_q8,
            cfg,
            SRM_LUT_Q8[count],
        )
        stochastic_sndr.append(spectrum_metrics(codes, cfg)["sndr_db"])

    backoff_cfg = replace(cfg, sine_amplitude_code=BACKOFF_AMPLITUDE)
    backoff_sine, _, _ = coherent_sine(backoff_cfg, chip_id=1)
    backoff_direct = np.floor(backoff_sine + 0.5).astype(np.int32)
    backoff_direct_metrics = spectrum_metrics(backoff_direct, backoff_cfg)

    passed = bool(
        direct_metrics["sndr_db"] >= IDEAL_SNDR_MIN_DB
        and expected_metrics["sndr_db"] >= IDEAL_SNDR_MIN_DB
        and exact_residue_metrics["sndr_db"] >= IDEAL_SNDR_MIN_DB
    )
    if not passed:
        raise RuntimeError("ideal 16-bit arithmetic gate failed")
    return {
        "theoretical_full_scale_sndr_db": 6.02 * cfg.output_bits + 1.76,
        "threshold_db": IDEAL_SNDR_MIN_DB,
        "direct_quantizer_full_scale": direct_metrics,
        "direct_quantizer_backoff": backoff_direct_metrics,
        "segmented_cdac_no_srm": no_srm_metrics,
        "segmented_cdac_exact_physical_residue": exact_residue_metrics,
        "segmented_cdac_expected_srm": expected_metrics,
        "rtl_22_stochastic_srm_sndr_db": summarize(stochastic_sndr),
        "passed": passed,
    }


def dynamic_capture(
    cfg: FullSarConfig,
    physical_q8: np.ndarray,
    chip_id: int,
    stream_id: int,
    phase_chip_id: int,
) -> Tuple[object, np.ndarray]:
    sine, _, _ = coherent_sine(cfg, phase_chip_id)
    conversion = run_normal_sar_conversion(
        sine,
        physical_q8,
        cfg,
        chip_id,
        stream_id=stream_id,
        include_random_noise=False,
        stochastic_srm=True,
    )
    return conversion, sine


def evaluate_main_chip(
    chip_id: int,
    cfg: FullSarConfig,
    physical_cfg: PhysicalCdacConfig,
) -> Tuple[List[Dict[str, object]], Dict[str, object]]:
    chip = draw_physical_chip(physical_cfg, chip_id)
    physical_q8 = chip.weights_q8
    nominal_q8 = nominal_weights_q8(physical_cfg)
    weights, normalization_scales = decoder_weight_set(
        physical_q8, nominal_q8, cfg, chip_id
    )

    full_cfg = replace(cfg, sine_amplitude_code=FULL_SCALE_AMPLITUDE)
    backoff_cfg = replace(cfg, sine_amplitude_code=BACKOFF_AMPLITUDE)
    full_conversion, _ = dynamic_capture(
        full_cfg, physical_q8, chip_id, 8101, chip_id
    )
    backoff_conversion, _ = dynamic_capture(
        backoff_cfg, physical_q8, chip_id, 8102, chip_id + 10000
    )
    ramp = full_scale_ramp(cfg)
    ramp_conversion = run_normal_sar_conversion(
        ramp,
        physical_q8,
        cfg,
        chip_id,
        stream_id=8103,
        include_random_noise=False,
        stochastic_srm=False,
    )

    full_codes: Dict[str, np.ndarray] = {}
    backoff_codes: Dict[str, np.ndarray] = {}
    ramp_codes: Dict[str, np.ndarray] = {}
    full_sat: Dict[str, float] = {}
    backoff_sat: Dict[str, float] = {}
    ramp_sat: Dict[str, float] = {}
    for name, decoder_weights in weights.items():
        full_codes[name], full_sat[name] = rtl_reconstruct(
            full_conversion.raw_bits,
            decoder_weights,
            full_cfg,
            full_conversion.srm_residue_q8,
        )
        backoff_codes[name], backoff_sat[name] = rtl_reconstruct(
            backoff_conversion.raw_bits,
            decoder_weights,
            backoff_cfg,
            backoff_conversion.srm_residue_q8,
        )
        ramp_codes[name], ramp_sat[name] = rtl_reconstruct(
            ramp_conversion.raw_bits,
            decoder_weights,
            cfg,
            ramp_conversion.srm_residue_q8,
        )

    rows: List[Dict[str, object]] = []
    for name in DECODERS:
        full = spectrum_metrics(full_codes[name], full_cfg)
        backoff = spectrum_metrics(backoff_codes[name], backoff_cfg)
        static = linearity_metrics(ramp_codes[name], cfg)
        code_rmse, code_max, code_gain, code_offset = affine_error(
            ramp_codes["ORACLE_SRM"], ramp_codes[name]
        )
        weight_rmse, weight_max, weight_gain = weight_error(
            physical_q8, weights[name], cfg.frac_bits
        )
        rows.append(
            {
                "chip_id": chip_id,
                "decoder": name,
                "fullscale_sndr_db": full["sndr_db"],
                "fullscale_snr_db": full["snr_db"],
                "fullscale_sfdr_db": full["sfdr_db"],
                "fullscale_thd_db": full["thd_db"],
                "fullscale_enob": full["enob"],
                "fullscale_saturation_fraction": full_sat[name],
                "backoff_sndr_db": backoff["sndr_db"],
                "backoff_snr_db": backoff["snr_db"],
                "backoff_sfdr_db": backoff["sfdr_db"],
                "backoff_thd_db": backoff["thd_db"],
                "backoff_enob": backoff["enob"],
                "backoff_saturation_fraction": backoff_sat[name],
                "dnl_min_lsb": static["dnl_min_lsb"],
                "dnl_max_lsb": static["dnl_max_lsb"],
                "inl_min_lsb": static["inl_min_lsb"],
                "inl_max_lsb": static["inl_max_lsb"],
                "missing_codes": static["missing_codes"],
                "ramp_saturation_fraction": ramp_sat[name],
                "code_rmse_to_oracle_affine_lsb": code_rmse,
                "code_max_to_oracle_affine_lsb": code_max,
                "code_gain_to_oracle": code_gain,
                "code_offset_to_oracle_lsb": code_offset,
                "weight_rmse_gain_aligned_lsb": weight_rmse,
                "weight_max_gain_aligned_lsb": weight_max,
                "weight_gain_to_oracle": weight_gain,
                "sum_normalization_scale": normalization_scales.get(name, 1.0),
            }
        )
    return rows, physical_row(chip, physical_cfg)


def evaluate_sigma_chip(
    sigma_pct: float,
    chip_id: int,
    cfg: FullSarConfig,
    physical_cfg: PhysicalCdacConfig,
) -> List[Dict[str, object]]:
    local_physical = replace(physical_cfg, unit_cap_sigma_pct=float(sigma_pct))
    chip = draw_physical_chip(local_physical, chip_id)
    nominal_q8 = nominal_weights_q8(local_physical)
    weights, _ = decoder_weight_set(chip.weights_q8, nominal_q8, cfg, chip_id)
    conversion, _ = dynamic_capture(
        cfg,
        chip.weights_q8,
        chip_id,
        8201 + int(round(sigma_pct * 100)),
        chip_id + 20000,
    )
    rows = []
    for name in SWEEP_DECODERS:
        codes, saturation = rtl_reconstruct(
            conversion.raw_bits,
            weights[name],
            cfg,
            conversion.srm_residue_q8,
        )
        metrics = spectrum_metrics(codes, cfg)
        weight_rmse, _, _ = weight_error(
            chip.weights_q8, weights[name], cfg.frac_bits
        )
        rows.append(
            {
                "unit_cap_sigma_pct": float(sigma_pct),
                "chip_id": chip_id,
                "decoder": name,
                "sndr_db": metrics["sndr_db"],
                "sfdr_db": metrics["sfdr_db"],
                "enob": metrics["enob"],
                "saturation_fraction": saturation,
                "weight_rmse_gain_aligned_lsb": weight_rmse,
            }
        )
    return rows


def evaluate_amplitude_chip(
    chip_id: int,
    amplitude_ratios: Sequence[float],
    cfg: FullSarConfig,
    physical_cfg: PhysicalCdacConfig,
) -> List[Dict[str, object]]:
    chip = draw_physical_chip(physical_cfg, chip_id)
    nominal_q8 = nominal_weights_q8(physical_cfg)
    weights, _ = decoder_weight_set(chip.weights_q8, nominal_q8, cfg, chip_id)
    rows = []
    for index, ratio in enumerate(amplitude_ratios):
        local_cfg = replace(cfg, sine_amplitude_code=float(ratio) * 32768.0)
        conversion, _ = dynamic_capture(
            local_cfg,
            chip.weights_q8,
            chip_id,
            8301 + index,
            chip_id + 30000 + index,
        )
        for name in SWEEP_DECODERS:
            codes, saturation = rtl_reconstruct(
                conversion.raw_bits,
                weights[name],
                local_cfg,
                conversion.srm_residue_q8,
            )
            metrics = spectrum_metrics(codes, local_cfg)
            rows.append(
                {
                    "amplitude_ratio": float(ratio),
                    "chip_id": chip_id,
                    "decoder": name,
                    "sndr_db": metrics["sndr_db"],
                    "sfdr_db": metrics["sfdr_db"],
                    "enob": metrics["enob"],
                    "saturation_fraction": saturation,
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


def aggregate_decoders(
    rows: Sequence[Dict[str, object]],
    decoders: Sequence[str],
    excluded: Sequence[str],
) -> Dict[str, object]:
    metrics = [key for key in rows[0] if key not in excluded]
    return {
        decoder: {
            metric: summarize(
                float(row[metric]) for row in rows if row["decoder"] == decoder
            )
            for metric in metrics
        }
        for decoder in decoders
    }


def aggregate_sweep(
    rows: Sequence[Dict[str, object]],
    axis_key: str,
) -> List[Dict[str, object]]:
    output = []
    axis_values = sorted({float(row[axis_key]) for row in rows})
    metrics = [
        key
        for key in rows[0]
        if key not in {axis_key, "chip_id", "decoder"}
    ]
    for axis_value in axis_values:
        for decoder in SWEEP_DECODERS:
            selected = [
                row
                for row in rows
                if float(row[axis_key]) == axis_value and row["decoder"] == decoder
            ]
            for metric in metrics:
                output.append(
                    {
                        axis_key: axis_value,
                        "decoder": decoder,
                        "metric": metric,
                        **summarize(float(row[metric]) for row in selected),
                    }
                )
    return output


def pass_rate_summary(rows: Sequence[Dict[str, object]]) -> Dict[str, object]:
    output: Dict[str, object] = {}
    thresholds = (90.0, 94.0, 95.0, 96.0)
    for decoder in (
        "CAL_CURRENT_SRM",
        "CAL_SUM_NORM_SRM",
        "CAL_HEADROOM_GUARD_SRM",
    ):
        selected = [row for row in rows if row["decoder"] == decoder]
        output[decoder] = {}
        for condition in ("fullscale", "backoff"):
            values = np.array(
                [float(row[f"{condition}_sndr_db"]) for row in selected]
            )
            output[decoder][condition] = {
                f"ge_{threshold:g}_db": int(np.sum(values >= threshold))
                for threshold in thresholds
            }
            output[decoder][condition]["total"] = int(values.size)
    return output


def write_csv(rows: Sequence[Dict[str, object]], path: Path) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def plot_main(summary: Dict[str, object], outdir: Path) -> None:
    labels = ["Nominal", "Current", "Sum norm", "Guard", "Zero-error", "Oracle"]
    colors = ["#737373", "#147d92", "#d07a2d", "#b24a62", "#299c59", "#6d5aa8"]
    fig, axes = plt.subplots(2, 2, figsize=(12.0, 8.0))
    definitions = (
        ("fullscale_sndr_db", "Full-scale stochastic-SRM SNDR", "dB", False),
        ("backoff_sndr_db", "-1.72 dBFS stochastic-SRM SNDR", "dB", False),
        ("weight_rmse_gain_aligned_lsb", "Gain-aligned weight error", "LSB rms", True),
        ("code_rmse_to_oracle_affine_lsb", "Ramp code error to oracle", "LSB rms", True),
    )
    for axis, (metric, title, ylabel, logarithmic) in zip(axes.flat, definitions):
        median = np.array([summary[name][metric]["median"] for name in DECODERS])
        p05 = np.array([summary[name][metric]["p05"] for name in DECODERS])
        p95 = np.array([summary[name][metric]["p95"] for name in DECODERS])
        display = np.maximum(median, 1e-5)
        bars = axis.bar(labels, display, color=colors, width=0.68)
        axis.errorbar(
            labels,
            display,
            yerr=np.vstack(
                (display - np.maximum(p05, 1e-5), np.maximum(p95, display) - display)
            ),
            fmt="none",
            color="black",
            capsize=3,
        )
        if logarithmic:
            axis.set_yscale("log")
        axis.bar_label(bars, labels=[f"{value:.3g}" for value in median], padding=3, fontsize=8)
        axis.set_title(title)
        axis.set_ylabel(ylabel)
        axis.grid(axis="y", alpha=0.25)
        axis.tick_params(axis="x", rotation=18)
    fig.suptitle("Physical segmented-CDAC revalidation, 512 chips")
    fig.tight_layout()
    fig.savefig(outdir / "fig_revalidation_main.png", dpi=180)
    fig.savefig(outdir / "fig_revalidation_main.pdf")
    plt.close(fig)


def plot_static(summary: Dict[str, object], outdir: Path) -> None:
    labels = ["Nominal", "Current", "Sum norm", "Guard", "Zero-error", "Oracle"]
    colors = ["#737373", "#147d92", "#d07a2d", "#b24a62", "#299c59", "#6d5aa8"]
    fig, axes = plt.subplots(1, 3, figsize=(12.0, 4.2))
    metrics = (
        ("dnl_max_lsb", "DNL max median", "LSB"),
        ("inl_max_lsb", "INL max median", "LSB"),
        ("missing_codes", "Missing codes median", "codes"),
    )
    for axis, (metric, title, ylabel) in zip(axes, metrics):
        values = np.array([summary[name][metric]["median"] for name in DECODERS])
        bars = axis.bar(labels, values, color=colors, width=0.68)
        axis.bar_label(bars, labels=[f"{value:.3g}" for value in values], padding=3, fontsize=8)
        axis.set_title(title)
        axis.set_ylabel(ylabel)
        axis.grid(axis="y", alpha=0.25)
        axis.tick_params(axis="x", rotation=18)
    fig.suptitle("Deterministic full-range static transfer")
    fig.tight_layout()
    fig.savefig(outdir / "fig_revalidation_static.png", dpi=180)
    fig.savefig(outdir / "fig_revalidation_static.pdf")
    plt.close(fig)


def plot_sweep(
    rows: Sequence[Dict[str, object]],
    axis_key: str,
    outdir: Path,
    filename: str,
    title: str,
) -> None:
    styles = {
        "NOMINAL_SRM": ("Nominal", "#737373", "--"),
        "CAL_CURRENT_SRM": ("Current", "#147d92", "-"),
        "CAL_SUM_NORM_SRM": ("Sum norm", "#d07a2d", "-"),
        "CAL_HEADROOM_GUARD_SRM": ("Headroom guard", "#b24a62", "-"),
        "ORACLE_SRM": ("Oracle", "#6d5aa8", ":"),
    }
    fig, axes = plt.subplots(1, 2, figsize=(10.5, 4.3))
    for axis, metric, ylabel in (
        (axes[0], "sndr_db", "SNDR median (dB)"),
        (axes[1], "saturation_fraction", "Saturation median"),
    ):
        for decoder, (label, color, line_style) in styles.items():
            selected = sorted(
                [row for row in rows if row["decoder"] == decoder and row["metric"] == metric],
                key=lambda row: float(row[axis_key]),
            )
            x = np.array([float(row[axis_key]) for row in selected])
            y = np.array([float(row["median"]) for row in selected])
            axis.plot(x, y, marker="o", color=color, linestyle=line_style, label=label)
        axis.set_xlabel(axis_key.replace("_", " "))
        axis.set_ylabel(ylabel)
        axis.grid(True, alpha=0.3)
        axis.legend(fontsize=8)
    fig.suptitle(title)
    fig.tight_layout()
    fig.savefig(outdir / f"{filename}.png", dpi=180)
    fig.savefig(outdir / f"{filename}.pdf")
    plt.close(fig)


def run_campaign(
    cfg: FullSarConfig,
    physical_cfg: PhysicalCdacConfig,
    outdir: Path,
    workers: int,
    sensitivity_chips: int,
    amplitude_chips: int,
    sigma_values: Sequence[float],
    amplitude_ratios: Sequence[float],
) -> Dict[str, object]:
    cfg.validate()
    physical_cfg.validate()
    outdir.mkdir(parents=True, exist_ok=True)
    ideal = ideal_acceptance()

    main_rows: List[Dict[str, object]] = []
    physical_rows: List[Dict[str, object]] = []
    with ProcessPoolExecutor(max_workers=workers) as executor:
        futures = {
            executor.submit(evaluate_main_chip, chip_id, cfg, physical_cfg): chip_id
            for chip_id in range(cfg.n_chips)
        }
        for completed, future in enumerate(as_completed(futures), start=1):
            rows, physical = future.result()
            main_rows.extend(rows)
            physical_rows.append(physical)
            if completed % 16 == 0 or completed == cfg.n_chips:
                print(f"Main {completed}/{cfg.n_chips}", flush=True)

    main_rows.sort(key=lambda row: (int(row["chip_id"]), DECODERS.index(str(row["decoder"]))))
    physical_rows.sort(key=lambda row: int(row["chip_id"]))
    main_summary = aggregate_decoders(
        main_rows, DECODERS, ("chip_id", "decoder")
    )
    physical_summary = {
        metric: summarize(float(row[metric]) for row in physical_rows)
        for metric in physical_rows[0]
        if metric != "chip_id"
    }

    sensitivity_cfg = noiseless_config(
        sensitivity_chips, n_fft=4096, amplitude_code=BACKOFF_AMPLITUDE
    )
    sigma_rows: List[Dict[str, object]] = []
    sigma_jobs = [
        (sigma, chip_id)
        for sigma in sigma_values
        for chip_id in range(sensitivity_chips)
    ]
    with ProcessPoolExecutor(max_workers=workers) as executor:
        futures = {
            executor.submit(
                evaluate_sigma_chip,
                sigma,
                chip_id,
                sensitivity_cfg,
                physical_cfg,
            ): (sigma, chip_id)
            for sigma, chip_id in sigma_jobs
        }
        for completed, future in enumerate(as_completed(futures), start=1):
            sigma_rows.extend(future.result())
            if completed % 64 == 0 or completed == len(sigma_jobs):
                print(f"Sigma sweep {completed}/{len(sigma_jobs)}", flush=True)
    sigma_rows.sort(
        key=lambda row: (
            float(row["unit_cap_sigma_pct"]),
            int(row["chip_id"]),
            SWEEP_DECODERS.index(str(row["decoder"])),
        )
    )
    sigma_summary = aggregate_sweep(sigma_rows, "unit_cap_sigma_pct")

    amplitude_cfg = noiseless_config(amplitude_chips, n_fft=4096)
    amplitude_rows: List[Dict[str, object]] = []
    with ProcessPoolExecutor(max_workers=workers) as executor:
        futures = {
            executor.submit(
                evaluate_amplitude_chip,
                chip_id,
                amplitude_ratios,
                amplitude_cfg,
                physical_cfg,
            ): chip_id
            for chip_id in range(amplitude_chips)
        }
        for completed, future in enumerate(as_completed(futures), start=1):
            amplitude_rows.extend(future.result())
            if completed % 16 == 0 or completed == amplitude_chips:
                print(f"Amplitude sweep {completed}/{amplitude_chips}", flush=True)
    amplitude_rows.sort(
        key=lambda row: (
            float(row["amplitude_ratio"]),
            int(row["chip_id"]),
            SWEEP_DECODERS.index(str(row["decoder"])),
        )
    )
    amplitude_summary = aggregate_sweep(amplitude_rows, "amplitude_ratio")

    write_csv(main_rows, outdir / "per_chip_main_metrics.csv")
    write_csv(physical_rows, outdir / "per_chip_physical_metrics.csv")
    write_csv(sigma_rows, outdir / "per_chip_sigma_metrics.csv")
    write_csv(sigma_summary, outdir / "sigma_summary.csv")
    write_csv(amplitude_rows, outdir / "per_chip_amplitude_metrics.csv")
    write_csv(amplitude_summary, outdir / "amplitude_summary.csv")
    plot_main(main_summary, outdir)
    plot_static(main_summary, outdir)
    plot_sweep(
        sigma_summary,
        "unit_cap_sigma_pct",
        outdir,
        "fig_revalidation_sigma_sweep",
        "Backed-off dynamic sensitivity to physical unit-cap mismatch",
    )
    plot_sweep(
        amplitude_summary,
        "amplitude_ratio",
        outdir,
        "fig_revalidation_amplitude_sweep",
        "Amplitude, stochastic SRM, and full-scale saturation",
    )

    payload = {
        "status": "complete",
        "experiment_version": "3.0",
        "scope": (
            "Physical 6+4+5+5 capacitor mismatch is solved before Q8 reconstruction. "
            "Dynamic paths retain 22-decision stochastic SRM and disable ordinary conversion noise. "
            "Static paths use expected-count SRM."
        ),
        "evidence_boundary": (
            "Behavioral L2 plus independent RTL regression. Mismatch centers are project MATLAB assumptions, "
            "not PDK signoff. Split-sampling VCM/AZ/flash/charge-injection timing is not modeled."
        ),
        "config": asdict(cfg),
        "physical_config": asdict(physical_cfg),
        "dynamic_conditions": {
            "full_scale_amplitude_code": FULL_SCALE_AMPLITUDE,
            "backoff_amplitude_code": BACKOFF_AMPLITUDE,
        },
        "ideal_acceptance": ideal,
        "main_completed_chips": cfg.n_chips,
        "sensitivity_chips_per_sigma": sensitivity_chips,
        "amplitude_sweep_chips": amplitude_chips,
        "sigma_values_pct": list(map(float, sigma_values)),
        "amplitude_ratios": list(map(float, amplitude_ratios)),
        "pass_rates": pass_rate_summary(main_rows),
        "main_summary": main_summary,
        "physical_summary": physical_summary,
        "sigma_summary": sigma_summary,
        "amplitude_summary": amplitude_summary,
    }
    (outdir / "summary.json").write_text(
        json.dumps(payload, indent=2), encoding="utf-8"
    )
    return payload


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chips", type=int, default=512)
    parser.add_argument("--sensitivity-chips", type=int, default=128)
    parser.add_argument("--amplitude-chips", type=int, default=128)
    parser.add_argument(
        "--workers",
        type=int,
        default=max(1, min(8, (os.cpu_count() or 2) // 2)),
    )
    parser.add_argument("--outdir", type=Path, default=DEFAULT_OUTDIR)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    cfg = noiseless_config(args.chips)
    payload = run_campaign(
        cfg=cfg,
        physical_cfg=PhysicalCdacConfig(),
        outdir=args.outdir,
        workers=max(1, args.workers),
        sensitivity_chips=args.sensitivity_chips,
        amplitude_chips=args.amplitude_chips,
        sigma_values=(0.0, 0.5, 1.0, 1.2, 1.5, 2.0, 3.0),
        amplitude_ratios=(0.70, 0.82, 0.90, 0.95, 0.99995),
    )
    ideal = payload["ideal_acceptance"]
    print("\nIdeal arithmetic gate")
    print(
        f"direct={ideal['direct_quantizer_full_scale']['sndr_db']:.3f} dB, "
        f"expected-SRM={ideal['segmented_cdac_expected_srm']['sndr_db']:.3f} dB, "
        f"stochastic-22 median={ideal['rtl_22_stochastic_srm_sndr_db']['median']:.3f} dB"
    )
    print("\nMain medians")
    for decoder in DECODERS:
        metrics = payload["main_summary"][decoder]
        print(
            f"{decoder:24s} full={metrics['fullscale_sndr_db']['median']:.3f} dB, "
            f"backoff={metrics['backoff_sndr_db']['median']:.3f} dB, "
            f"sat={metrics['fullscale_saturation_fraction']['median']:.6f}"
        )
    print(f"Artifacts: {args.outdir.resolve()}")


if __name__ == "__main__":
    main()

"""Run the 16-bit on-chip self-calibration behavioral experiment.

The calibration source of truth is the project implementation mirrored by
``analysis.full_sar_behavioral_20260729.full_sar_model``:

* 20 signed SAR decisions for a 16-bit output;
* six trusted LSB reference decisions;
* recursive calibration of bits 6 through 19;
* 32 P/N offset-cancelled measurement pairs per target bit;
* protected searches for bits 18 and 19;
* signed Q8 weight writeback;
* 22-decision SRM residue estimation and RTL-equivalent reconstruction.

ADCToolbox is used for standardized FFT and ramp-histogram metrics. Its
sine-fit weight solver is executed only as an explicitly named external
foreground-calibration baseline; it is not the project's on-chip self-cal.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from dataclasses import asdict, replace
from importlib.metadata import version
from pathlib import Path
from typing import Any, Dict, Iterable, Mapping, Tuple

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import adctoolbox
from adctoolbox.calibration import (
    calibrate_weight_sine,
    diagnose_calibration_matrix,
    scale_calibration_output,
)

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
)


EXPERIMENT_NAME = "SAR16B_ONCHIP_SELF_CAL_WITH_ADCTOOLBOX_ANALYSIS"
EXTERNAL_BASELINE = "ADCTOOLBOX_SINE_EXTERNAL_BASELINE"
REVIEWED_ADCTOOLBOX_COMMIT = "a8995cf4faf73dde9918589bfeb866c6a77db12d"
SRM_NOISE_ABLATION_SIGMA_LSB = 0.50
SRM_NOISE_ABLATION_AMPLITUDE = 0.90


def make_self_cal_config(n_fft: int) -> FullSarConfig:
    """Create the noise-isolated 16-bit experiment configuration."""

    cfg = FullSarConfig(
        cap_num=20,
        output_bits=16,
        frac_bits=8,
        max_calib_bit=5,
        avg_loops=32,
        srm_decisions=22,
        n_chips=1,
        n_fft=n_fft,
        fs_hz=5.0e6,
        fin_target_hz=0.71e6,
        sine_amplitude_code=0.995 * 32767.0,
        static_samples_per_code=2,
        calibration_comparator_offset_lsb=5.0,
        calibration_comparator_noise_lsb=0.50,
        sampling_noise_lsb=0.0,
        normal_comparator_noise_lsb=0.0,
        normal_comparator_offset_lsb=0.0,
        reference_noise_rms_fraction=0.0,
        dac_settling_error_fraction=0.0,
        srm_comparator_noise_lsb=0.50,
        srm_comparator_offset_lsb=0.0,
    )
    cfg.validate()
    return cfg


def gain_aligned_rmse_lsb(reference_q8: np.ndarray, estimate_q8: np.ndarray) -> float:
    """Return RMS weight error after removing one global digital gain."""

    reference = np.asarray(reference_q8, dtype=float)
    estimate = np.asarray(estimate_q8, dtype=float)
    denominator = float(np.dot(estimate, estimate))
    gain = float(np.dot(reference, estimate) / denominator) if denominator > 0.0 else 1.0
    return float(np.sqrt(np.mean((gain * estimate - reference) ** 2)) / 256.0)


def direct_weight_rmse_lsb(reference_q8: np.ndarray, estimate_q8: np.ndarray) -> float:
    """Return direct RMS weight error in final-code LSB units."""

    error_q8 = np.asarray(estimate_q8, dtype=float) - np.asarray(reference_q8, dtype=float)
    return float(np.sqrt(np.mean(error_q8**2)) / 256.0)


def gain_to_align_estimate(reference_q8: np.ndarray, estimate_q8: np.ndarray) -> float:
    """Return the scalar gain that best aligns an estimate to the reference."""

    reference = np.asarray(reference_q8, dtype=float)
    estimate = np.asarray(estimate_q8, dtype=float)
    denominator = float(np.dot(estimate, estimate))
    return float(np.dot(reference, estimate) / denominator) if denominator > 0.0 else 1.0


def run_external_sine_baseline(
    bits_train: np.ndarray,
    normalized_frequency: float,
    nominal_q8: np.ndarray,
) -> Tuple[np.ndarray, Dict[str, Any], Dict[str, Any]]:
    """Run ADCToolbox sine fitting as a non-on-chip comparison baseline."""

    result = calibrate_weight_sine(
        np.asarray(bits_train, dtype=float),
        freq=float(normalized_frequency),
        force_search=False,
        nominal_weights=np.asarray(nominal_q8, dtype=float),
        harmonic_order=1,
        verbose=0,
    )
    scaled = scale_calibration_output(result, target_weights=nominal_q8)
    weights_q8 = np.asarray(scaled["weight"], dtype=float)
    if weights_q8.shape != np.asarray(nominal_q8).shape:
        raise RuntimeError("ADCToolbox returned an unexpected weight-vector shape.")
    if not np.all(np.isfinite(weights_q8)):
        raise RuntimeError("ADCToolbox returned non-finite external-baseline weights.")

    diagnostic = diagnose_calibration_matrix(
        bits_train,
        nominal_weights=nominal_q8,
        weights=weights_q8,
    )
    compact_result = {
        "refined_frequency": float(
            np.asarray(result["refined_frequency"]).reshape(-1)[0]
        ),
        "initial_frequency": float(np.asarray(result["initial_frequency"]).reshape(-1)[0]),
        "scale_factor": float(scaled["scale_factor"]),
        "scale_convention": str(scaled["scale_convention"]),
        "rank_patch_applied": bool(result["rank_patch"]["applied"]),
        "bit_width_effective": int(result["rank_patch"]["bit_width_effective"]),
        "dropped_constant_bits": np.asarray(
            result["rank_patch"]["dropped_constant_bits"], dtype=int
        ).tolist(),
        "unmapped_bits": np.asarray(result["rank_patch"]["unmapped_bits"], dtype=int).tolist(),
    }
    compact_diagnostic = {
        "shape": [int(value) for value in diagnostic["shape"]],
        "is_binary": bool(diagnostic["is_binary"]),
        "binary_violation_fraction": float(diagnostic["binary_violation_fraction"]),
        "rank": int(diagnostic["rank"]),
        "rank_with_offset": int(diagnostic["rank_with_offset"]),
        "condition_number": float(diagnostic["condition_number"]),
        "near_constant_columns": np.asarray(
            diagnostic["near_constant_columns"], dtype=int
        ).tolist(),
        "weight_diagnostics": {
            key: _json_ready(value)
            for key, value in diagnostic["weight_diagnostics"].items()
        },
    }
    return weights_q8, compact_result, compact_diagnostic


def _dynamic_decode_cases(
    cfg: FullSarConfig,
    nominal_q8: np.ndarray,
    physical_q8: np.ndarray,
    self_cal_q8: np.ndarray,
    external_q8: np.ndarray,
    expected_conversion: Any,
    stochastic_conversion: Any,
) -> Dict[str, Tuple[np.ndarray, np.ndarray | int]]:
    """Define dynamic decoders while preserving one common raw-bit stream."""

    if not np.array_equal(expected_conversion.raw_bits, stochastic_conversion.raw_bits):
        raise RuntimeError("SRM mode changed the normal-conversion SAR bit decisions.")
    return {
        "NOMINAL_Q8_NO_SRM": (nominal_q8, 0),
        "NOMINAL_Q8_EXACT_RESIDUE": (
            nominal_q8,
            expected_conversion.physical_residue_q8,
        ),
        "SELF_CAL_Q8_NO_SRM": (self_cal_q8, 0),
        "SELF_CAL_Q8_SRM_EXPECTED": (
            self_cal_q8,
            expected_conversion.srm_residue_q8,
        ),
        "SELF_CAL_Q8_SRM_22_STOCHASTIC": (
            self_cal_q8,
            stochastic_conversion.srm_residue_q8,
        ),
        "SELF_CAL_Q8_EXACT_RESIDUE": (
            self_cal_q8,
            expected_conversion.physical_residue_q8,
        ),
        "ORACLE_Q8_NO_SRM": (physical_q8, 0),
        "ORACLE_Q8_SRM_EXPECTED": (
            physical_q8,
            expected_conversion.srm_residue_q8,
        ),
        "ORACLE_Q8_EXACT_RESIDUE": (
            physical_q8,
            expected_conversion.physical_residue_q8,
        ),
        EXTERNAL_BASELINE: (external_q8, expected_conversion.srm_residue_q8),
    }


def _static_decode_cases(
    nominal_q8: np.ndarray,
    physical_q8: np.ndarray,
    self_cal_q8: np.ndarray,
    external_q8: np.ndarray,
    conversion: Any,
) -> Dict[str, Tuple[np.ndarray, np.ndarray | int]]:
    """Define deterministic ramp decoders for DNL/INL extraction."""

    return {
        "NOMINAL_Q8_NO_SRM": (nominal_q8, 0),
        "NOMINAL_Q8_EXACT_RESIDUE": (
            nominal_q8,
            conversion.physical_residue_q8,
        ),
        "SELF_CAL_Q8_NO_SRM": (self_cal_q8, 0),
        "SELF_CAL_Q8_SRM_EXPECTED": (self_cal_q8, conversion.srm_residue_q8),
        # Static linearity must remain deterministic. The stochastic dynamic
        # case therefore shares the expected-count SRM transfer curve here.
        "SELF_CAL_Q8_SRM_22_STOCHASTIC": (
            self_cal_q8,
            conversion.srm_residue_q8,
        ),
        "SELF_CAL_Q8_EXACT_RESIDUE": (
            self_cal_q8,
            conversion.physical_residue_q8,
        ),
        "ORACLE_Q8_NO_SRM": (physical_q8, 0),
        "ORACLE_Q8_SRM_EXPECTED": (physical_q8, conversion.srm_residue_q8),
        "ORACLE_Q8_EXACT_RESIDUE": (physical_q8, conversion.physical_residue_q8),
        EXTERNAL_BASELINE: (external_q8, conversion.srm_residue_q8),
    }


def decode_cases(
    cases: Mapping[str, Tuple[np.ndarray, np.ndarray | int]],
    raw_bits: np.ndarray,
    cfg: FullSarConfig,
) -> Tuple[Dict[str, np.ndarray], Dict[str, float]]:
    """Apply RTL-equivalent reconstruction to each named decoder."""

    codes: Dict[str, np.ndarray] = {}
    saturation: Dict[str, float] = {}
    for name, (weights_q8, residue_q8) in cases.items():
        codes[name], saturation[name] = rtl_reconstruct(
            raw_bits,
            weights_q8,
            cfg,
            residue_q8,
        )
    return codes, saturation


def ideal_quantizer_control(cfg: FullSarConfig, chip_id: int) -> Dict[str, float]:
    """Measure a direct ideal 16-bit quantizer near full scale."""

    control_cfg = replace(cfg, fin_target_hz=0.97e6, sine_amplitude_code=32766.0)
    input_codes, fin_hz, fft_bin = coherent_sine(control_cfg, chip_id)
    quantized = np.clip(np.rint(input_codes), -32768, 32767).astype(np.int32)
    metrics = spectrum_metrics(quantized, control_cfg)
    return {
        **metrics,
        "fin_hz": float(fin_hz),
        "fft_bin": int(fft_bin),
        "theoretical_full_scale_sndr_db": float(6.02 * 16 + 1.76),
    }


def _affine_aligned_error_rmse_lsb(
    input_codes: np.ndarray,
    output_codes: np.ndarray,
) -> float:
    """Return output-error RMS after removing one gain and one offset.

    The alignment removes deterministic global gain/offset differences between
    the physical and calibrated weight domains. The remaining error therefore
    captures noise, quantization, and nonlinear reconstruction error in final
    16-bit code LSB units.
    """

    reference = np.asarray(input_codes, dtype=float)
    estimate = np.asarray(output_codes, dtype=float)
    reference_centered = reference - float(np.mean(reference))
    denominator = float(np.dot(reference_centered, reference_centered))
    gain = (
        float(np.dot(reference_centered, estimate - float(np.mean(estimate))))
        / denominator
        if denominator > 0.0
        else 1.0
    )
    offset = float(np.mean(estimate) - gain * np.mean(reference))
    residual = estimate - (gain * reference + offset)
    return float(np.sqrt(np.mean(residual**2)))


def _distribution_summary(values: Iterable[float]) -> Dict[str, float]:
    data = np.asarray(list(values), dtype=float)
    if data.size == 0:
        raise ValueError("Cannot summarize an empty distribution.")
    return {
        "mean": float(np.mean(data)),
        "std": float(np.std(data, ddof=1)) if data.size > 1 else 0.0,
        "min": float(np.min(data)),
        "p05": float(np.percentile(data, 5)),
        "median": float(np.percentile(data, 50)),
        "p95": float(np.percentile(data, 95)),
        "max": float(np.max(data)),
    }


def run_srm_noise_reduction_ablation(
    base_cfg: FullSarConfig,
    physical_q8: np.ndarray,
    self_cal_q8: np.ndarray,
    chip_id: int,
    repeat_count: int = 32,
) -> Tuple[Dict[str, Any], list[Dict[str, Any]]]:
    """Run a paired noisy normal-conversion SRM on/off experiment.

    Each repeat performs the noisy 20-decision SAR conversion exactly once.
    The no-SRM and 22-decision SRM decoders then consume the same raw-bit
    stream. This isolates the digital residue estimate from changes in the
    normal conversion. Sampling, reference, and settling noise remain disabled
    because the current behavioral SRM model is qualified only for the
    comparator/pre-amplifier and quantization-residue path.
    """

    if repeat_count < 2:
        raise ValueError("SRM noise ablation requires at least two repeats.")

    cfg = replace(
        base_cfg,
        n_fft=min(base_cfg.n_fft, 8192),
        fin_target_hz=0.71e6,
        sine_amplitude_code=SRM_NOISE_ABLATION_AMPLITUDE * 32767.0,
        sampling_noise_lsb=0.0,
        normal_comparator_noise_lsb=SRM_NOISE_ABLATION_SIGMA_LSB,
        normal_comparator_offset_lsb=0.0,
        reference_noise_rms_fraction=0.0,
        dac_settling_error_fraction=0.0,
        srm_comparator_noise_lsb=SRM_NOISE_ABLATION_SIGMA_LSB,
        srm_comparator_offset_lsb=0.0,
    )
    cfg.validate()
    input_codes, fin_hz, fft_bin = coherent_sine(cfg, chip_id)

    decoder_order = (
        "ORACLE_NO_SRM_NOISY",
        "ORACLE_SRM_22_NOISY",
        "ORACLE_SRM_EXPECTED_NOISY",
        "SELF_CAL_NO_SRM_NOISY",
        "SELF_CAL_SRM_22_NOISY",
    )
    rows: list[Dict[str, Any]] = []
    raw_bits_shared = True

    for repeat in range(repeat_count):
        stream_id = 12000 + repeat
        stochastic = run_normal_sar_conversion(
            input_codes,
            physical_q8,
            cfg,
            chip_id,
            stream_id=stream_id,
            include_random_noise=True,
            stochastic_srm=True,
        )
        expected = run_normal_sar_conversion(
            input_codes,
            physical_q8,
            cfg,
            chip_id,
            stream_id=stream_id,
            include_random_noise=True,
            stochastic_srm=False,
        )
        same_raw_bits = bool(np.array_equal(stochastic.raw_bits, expected.raw_bits))
        raw_bits_shared = raw_bits_shared and same_raw_bits
        if not same_raw_bits:
            raise RuntimeError("Expected/stochastic SRM changed the paired raw-bit stream.")

        cases = {
            "ORACLE_NO_SRM_NOISY": (physical_q8, 0),
            "ORACLE_SRM_22_NOISY": (physical_q8, stochastic.srm_residue_q8),
            "ORACLE_SRM_EXPECTED_NOISY": (physical_q8, expected.srm_residue_q8),
            "SELF_CAL_NO_SRM_NOISY": (self_cal_q8, 0),
            "SELF_CAL_SRM_22_NOISY": (
                self_cal_q8,
                stochastic.srm_residue_q8,
            ),
        }
        decoded, saturation = decode_cases(cases, stochastic.raw_bits, cfg)
        for decoder in decoder_order:
            dynamic = spectrum_metrics(decoded[decoder], cfg)
            rows.append(
                {
                    "repeat": repeat,
                    "decoder": decoder,
                    **dynamic,
                    "aligned_error_rmse_lsb": _affine_aligned_error_rmse_lsb(
                        input_codes,
                        decoded[decoder],
                    ),
                    "saturation_fraction": float(saturation[decoder]),
                }
            )

    by_decoder: Dict[str, Dict[str, Any]] = {}
    for decoder in decoder_order:
        decoder_rows = [row for row in rows if row["decoder"] == decoder]
        by_decoder[decoder] = {
            "sndr_db": _distribution_summary(row["sndr_db"] for row in decoder_rows),
            "sfdr_db": _distribution_summary(row["sfdr_db"] for row in decoder_rows),
            "aligned_error_rmse_lsb": _distribution_summary(
                row["aligned_error_rmse_lsb"] for row in decoder_rows
            ),
            "max_saturation_fraction": float(
                max(row["saturation_fraction"] for row in decoder_rows)
            ),
        }

    def paired_values(metric: str, with_srm: str, without_srm: str) -> np.ndarray:
        on = np.asarray(
            [row[metric] for row in rows if row["decoder"] == with_srm],
            dtype=float,
        )
        off = np.asarray(
            [row[metric] for row in rows if row["decoder"] == without_srm],
            dtype=float,
        )
        if on.shape != off.shape:
            raise RuntimeError("Paired SRM distributions have different shapes.")
        return on - off

    oracle_sndr_gain = paired_values(
        "sndr_db", "ORACLE_SRM_22_NOISY", "ORACLE_NO_SRM_NOISY"
    )
    self_cal_sndr_gain = paired_values(
        "sndr_db", "SELF_CAL_SRM_22_NOISY", "SELF_CAL_NO_SRM_NOISY"
    )
    oracle_rmse_ratio = np.asarray(
        [
            row["aligned_error_rmse_lsb"]
            for row in rows
            if row["decoder"] == "ORACLE_NO_SRM_NOISY"
        ],
        dtype=float,
    ) / np.asarray(
        [
            row["aligned_error_rmse_lsb"]
            for row in rows
            if row["decoder"] == "ORACLE_SRM_22_NOISY"
        ],
        dtype=float,
    )
    self_cal_rmse_ratio = np.asarray(
        [
            row["aligned_error_rmse_lsb"]
            for row in rows
            if row["decoder"] == "SELF_CAL_NO_SRM_NOISY"
        ],
        dtype=float,
    ) / np.asarray(
        [
            row["aligned_error_rmse_lsb"]
            for row in rows
            if row["decoder"] == "SELF_CAL_SRM_22_NOISY"
        ],
        dtype=float,
    )

    summary = {
        "classification": "paired_comparator_noise_and_residue_ablation",
        "repeat_count": repeat_count,
        "raw_bits_shared_between_srm_on_off": raw_bits_shared,
        "conditions": {
            "n_fft": cfg.n_fft,
            "fin_hz": float(fin_hz),
            "fft_bin": int(fft_bin),
            "sine_amplitude_fraction_of_positive_full_scale": (
                SRM_NOISE_ABLATION_AMPLITUDE
            ),
            "normal_comparator_noise_lsb": cfg.normal_comparator_noise_lsb,
            "srm_observation_noise_lsb": cfg.srm_comparator_noise_lsb,
            "srm_decisions": cfg.srm_decisions,
            "sampling_noise_lsb": cfg.sampling_noise_lsb,
            "reference_noise_rms_fraction": cfg.reference_noise_rms_fraction,
            "dac_settling_error_fraction": cfg.dac_settling_error_fraction,
        },
        "decoder_metrics": by_decoder,
        "paired_improvement": {
            "oracle_sndr_gain_db": _distribution_summary(oracle_sndr_gain),
            "self_cal_sndr_gain_db": _distribution_summary(self_cal_sndr_gain),
            "oracle_error_rmse_reduction_ratio": _distribution_summary(
                oracle_rmse_ratio
            ),
            "self_cal_error_rmse_reduction_ratio": _distribution_summary(
                self_cal_rmse_ratio
            ),
        },
        "evidence_boundary": (
            "This isolates comparator/pre-amplifier decision noise and held-residue "
            "estimation. It does not model split-sampling kT/C cancellation, AZ "
            "aliasing, transistor bandwidth, or the paper's complete 111-to-38-uVrms "
            "noise budget."
        ),
    }
    return summary, rows


def _summarize_metrics(
    dynamic_codes: Mapping[str, np.ndarray],
    static_codes: Mapping[str, np.ndarray],
    dynamic_saturation: Mapping[str, float],
    static_saturation: Mapping[str, float],
    cfg: FullSarConfig,
) -> Tuple[Dict[str, Dict[str, Any]], Dict[str, Dict[str, Any]]]:
    """Collect ADCToolbox dynamic and static metrics for every decoder."""

    summary: Dict[str, Dict[str, Any]] = {}
    linearity_arrays: Dict[str, Dict[str, Any]] = {}
    for name, codes in dynamic_codes.items():
        dynamic = spectrum_metrics(codes, cfg)
        static = linearity_metrics(static_codes[name], cfg)
        summary[name] = {
            **dynamic,
            "dynamic_saturation_fraction": float(dynamic_saturation[name]),
            "dnl_min_lsb": float(static["dnl_min_lsb"]),
            "dnl_max_lsb": float(static["dnl_max_lsb"]),
            "dnl_pp_lsb": float(static["dnl_pp_lsb"]),
            "inl_min_lsb": float(static["inl_min_lsb"]),
            "inl_max_lsb": float(static["inl_max_lsb"]),
            "inl_pp_lsb": float(static["inl_pp_lsb"]),
            "missing_codes": int(static["missing_codes"]),
            "static_saturation_fraction": float(static_saturation[name]),
        }
        linearity_arrays[name] = {
            "code": np.asarray(static["code"]),
            "dnl": np.asarray(static["dnl"]),
            "transition_code": np.asarray(static["transition_code"]),
            "inl": np.asarray(static["inl"]),
        }
    return summary, linearity_arrays


def _write_metrics_csv(path: Path, metrics: Mapping[str, Mapping[str, Any]]) -> None:
    fields = [
        "decoder",
        "sndr_db",
        "snr_db",
        "sfdr_db",
        "thd_db",
        "enob",
        "dynamic_saturation_fraction",
        "dnl_min_lsb",
        "dnl_max_lsb",
        "dnl_pp_lsb",
        "inl_min_lsb",
        "inl_max_lsb",
        "inl_pp_lsb",
        "missing_codes",
        "static_saturation_fraction",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for decoder, values in metrics.items():
            writer.writerow({"decoder": decoder, **{key: values[key] for key in fields[1:]}})


def _write_weights_csv(
    path: Path,
    nominal_q8: np.ndarray,
    physical_q8: np.ndarray,
    self_cal_q8: np.ndarray,
    external_q8: np.ndarray,
) -> None:
    fields = [
        "bit_lsb_first",
        "nominal_q8",
        "physical_q8",
        "self_cal_q8",
        "external_sine_q8",
        "nominal_error_lsb",
        "self_cal_error_lsb",
        "external_sine_error_lsb",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for bit in range(len(physical_q8)):
            writer.writerow(
                {
                    "bit_lsb_first": bit,
                    "nominal_q8": float(nominal_q8[bit]),
                    "physical_q8": float(physical_q8[bit]),
                    "self_cal_q8": float(self_cal_q8[bit]),
                    "external_sine_q8": float(external_q8[bit]),
                    "nominal_error_lsb": float((nominal_q8[bit] - physical_q8[bit]) / 256.0),
                    "self_cal_error_lsb": float((self_cal_q8[bit] - physical_q8[bit]) / 256.0),
                    "external_sine_error_lsb": float((external_q8[bit] - physical_q8[bit]) / 256.0),
                }
            )


def _write_srm_noise_ablation_csv(
    path: Path,
    rows: Iterable[Mapping[str, Any]],
) -> None:
    fields = [
        "repeat",
        "decoder",
        "sndr_db",
        "snr_db",
        "sfdr_db",
        "thd_db",
        "enob",
        "aligned_error_rmse_lsb",
        "saturation_fraction",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row[field] for field in fields})


def _relative_error_percent(reference: np.ndarray, estimate: np.ndarray) -> np.ndarray:
    reference = np.asarray(reference, dtype=float)
    return 100.0 * (np.asarray(estimate, dtype=float) / reference - 1.0)


def _plot_weight_error(
    path: Path,
    physical_q8: np.ndarray,
    nominal_q8: np.ndarray,
    self_cal_q8: np.ndarray,
    external_q8: np.ndarray,
) -> None:
    bits = np.arange(len(physical_q8))
    fig, ax = plt.subplots(figsize=(10.2, 5.2))
    ax.plot(bits, _relative_error_percent(physical_q8, nominal_q8), "o-", label="Nominal")
    ax.plot(bits, _relative_error_percent(physical_q8, self_cal_q8), "s-", label="On-chip self-cal")
    ax.plot(
        bits,
        _relative_error_percent(physical_q8, external_q8),
        "^-",
        label="ADCToolbox external sine fit",
    )
    ax.axhline(0.0, color="black", linewidth=0.8)
    ax.axvline(5.5, color="0.35", linestyle="--", linewidth=1.0, label="LSB reference boundary")
    ax.set_xlabel("Decision bit index (LSB first)")
    ax.set_ylabel("Weight estimation error (%)")
    ax.set_title("16-bit SAR weight estimation against the physical CDAC proxy")
    ax.set_xticks(bits)
    ax.grid(True, alpha=0.28)
    ax.legend(fontsize=8, ncol=2)
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)


def _spectrum_curve(codes: np.ndarray, fs_hz: float) -> Tuple[np.ndarray, np.ndarray]:
    values = np.asarray(codes, dtype=float) - float(np.mean(codes))
    power = np.abs(np.fft.rfft(values)) ** 2
    power[0] = 0.0
    reference = max(float(np.max(power)), np.finfo(float).tiny)
    spectrum_db = 10.0 * np.log10(np.maximum(power / reference, np.finfo(float).tiny))
    return np.fft.rfftfreq(len(values), 1.0 / fs_hz), spectrum_db


def _plot_spectrum(path: Path, codes: Mapping[str, np.ndarray], cfg: FullSarConfig) -> None:
    selected = [
        "NOMINAL_Q8_NO_SRM",
        "SELF_CAL_Q8_NO_SRM",
        "SELF_CAL_Q8_SRM_EXPECTED",
        "ORACLE_Q8_EXACT_RESIDUE",
        EXTERNAL_BASELINE,
    ]
    fig, ax = plt.subplots(figsize=(10.5, 5.8))
    for name in selected:
        frequency, spectrum_db = _spectrum_curve(codes[name], cfg.fs_hz)
        ax.plot(frequency / 1.0e6, spectrum_db, linewidth=0.9, label=name)
    ax.set_xlim(0.0, cfg.fs_hz / 2.0e6)
    ax.set_ylim(-150.0, 5.0)
    ax.set_xlabel("Frequency (MHz)")
    ax.set_ylabel("Magnitude relative to fundamental (dBc)")
    ax.set_title("Independent test-tone reconstruction spectrum")
    ax.grid(True, alpha=0.25)
    ax.legend(fontsize=7)
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)


def _plot_linearity(
    path: Path,
    linearity: Mapping[str, Mapping[str, np.ndarray]],
) -> None:
    selected = [
        "NOMINAL_Q8_NO_SRM",
        "SELF_CAL_Q8_NO_SRM",
        "SELF_CAL_Q8_SRM_EXPECTED",
        "ORACLE_Q8_EXACT_RESIDUE",
    ]
    fig, ax = plt.subplots(figsize=(10.5, 5.4))
    for name in selected:
        data = linearity[name]
        ax.plot(data["transition_code"], data["inl"], linewidth=0.9, label=name)
    ax.axhline(0.0, color="black", linewidth=0.8)
    ax.set_xlabel("Output code")
    ax.set_ylabel("Endpoint-corrected INL (LSB)")
    ax.set_title("Deterministic full-range ramp linearity")
    ax.grid(True, alpha=0.25)
    ax.legend(fontsize=7)
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)


def _plot_calibration_trace(path: Path, trace: Iterable[Mapping[str, Any]]) -> None:
    records = list(trace)
    bits = np.array([int(record["target_bit"]) for record in records])
    estimated = np.array([float(record["result_lsb"]) for record in records])
    physical = np.array([float(record["physical_lsb"]) for record in records])
    fig, ax = plt.subplots(figsize=(10.0, 5.2))
    ax.semilogy(bits, physical, "o-", label="Physical weight")
    ax.semilogy(bits, estimated, "s--", label="Self-calibrated Q8 weight")
    ax.set_xlabel("Calibrated decision bit (LSB first)")
    ax.set_ylabel("Weight (final-code LSB)")
    ax.set_title("Recursive P/N foreground self-calibration trace")
    ax.set_xticks(bits)
    ax.grid(True, which="both", alpha=0.28)
    ax.legend()
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)


def _plot_srm_noise_ablation(
    path: Path,
    rows: Iterable[Mapping[str, Any]],
) -> None:
    """Plot paired no-SRM/SRM results for identical noisy raw-bit streams."""

    records = list(rows)
    comparisons = (
        (
            "Oracle physical weights",
            "ORACLE_NO_SRM_NOISY",
            "ORACLE_SRM_22_NOISY",
            "#16697A",
            0,
        ),
        (
            "Project self-cal weights",
            "SELF_CAL_NO_SRM_NOISY",
            "SELF_CAL_SRM_22_NOISY",
            "#C44900",
            3,
        ),
    )
    fig, axes = plt.subplots(1, 2, figsize=(11.0, 5.0))
    metric_specs = (
        ("sndr_db", "SNDR (dB)"),
        ("aligned_error_rmse_lsb", "Affine-aligned error RMS (LSB)"),
    )
    for axis, (metric, ylabel) in zip(axes, metric_specs):
        for family, off_name, on_name, color, base in comparisons:
            off = np.asarray(
                [row[metric] for row in records if row["decoder"] == off_name],
                dtype=float,
            )
            on = np.asarray(
                [row[metric] for row in records if row["decoder"] == on_name],
                dtype=float,
            )
            for off_value, on_value in zip(off, on):
                axis.plot(
                    [base, base + 1],
                    [off_value, on_value],
                    color=color,
                    alpha=0.22,
                    linewidth=0.7,
                )
            axis.scatter(
                np.full(off.shape, base),
                off,
                color=color,
                s=13,
                alpha=0.70,
                label=family if metric == "sndr_db" else None,
            )
            axis.scatter(
                np.full(on.shape, base + 1),
                on,
                facecolor="white",
                edgecolor=color,
                linewidth=0.8,
                s=18,
                alpha=0.90,
            )
        axis.set_xticks([0, 1, 3, 4])
        axis.set_xticklabels(
            ["No SRM", "22-decision SRM", "No SRM", "22-decision SRM"],
            rotation=18,
        )
        axis.set_ylabel(ylabel)
        axis.grid(True, axis="y", alpha=0.25)
    axes[0].legend(fontsize=8, loc="best")
    fig.suptitle("Paired SRM noise-reduction ablation on identical noisy SAR decisions")
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)


def _json_ready(value: Any) -> Any:
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, np.generic):
        return value.item()
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, dict):
        return {str(key): _json_ready(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_ready(item) for item in value]
    if isinstance(value, float) and not math.isfinite(value):
        return str(value)
    return value


def run_experiment(
    output_dir: Path,
    chip_id: int = 17,
    n_fft: int = 16384,
    ramp_samples_per_code: int = 2,
    srm_noise_repeats: int = 32,
) -> Dict[str, Any]:
    """Execute one complete deterministic 16-bit self-calibration experiment."""

    output_dir.mkdir(parents=True, exist_ok=True)
    cfg = make_self_cal_config(n_fft)
    physical_cfg = PhysicalCdacConfig()
    physical_cfg.validate()
    chip = draw_physical_chip(physical_cfg, chip_id)

    nominal_q8 = nominal_weights_q8(physical_cfg)
    physical_q8 = np.asarray(chip.weights_q8, dtype=float)
    self_cal_q8, calibration_trace = run_rtl_equivalent_calibration(
        physical_q8,
        cfg,
        chip_id,
    )

    train_cfg = replace(cfg, fin_target_hz=0.71e6)
    test_cfg = replace(cfg, fin_target_hz=1.13e6)
    train_input, train_fin_hz, train_bin = coherent_sine(train_cfg, chip_id)
    test_input, test_fin_hz, test_bin = coherent_sine(test_cfg, chip_id)

    train_conversion = run_normal_sar_conversion(
        train_input,
        physical_q8,
        train_cfg,
        chip_id,
        stream_id=610,
        include_random_noise=False,
        stochastic_srm=False,
    )
    test_expected = run_normal_sar_conversion(
        test_input,
        physical_q8,
        test_cfg,
        chip_id,
        stream_id=620,
        include_random_noise=False,
        stochastic_srm=False,
    )
    test_stochastic = run_normal_sar_conversion(
        test_input,
        physical_q8,
        test_cfg,
        chip_id,
        stream_id=620,
        include_random_noise=False,
        stochastic_srm=True,
    )

    external_q8, external_result, external_diagnostic = run_external_sine_baseline(
        train_conversion.raw_bits,
        train_fin_hz / cfg.fs_hz,
        nominal_q8,
    )

    dynamic_cases = _dynamic_decode_cases(
        cfg,
        nominal_q8,
        physical_q8,
        self_cal_q8,
        external_q8,
        test_expected,
        test_stochastic,
    )
    dynamic_codes, dynamic_saturation = decode_cases(
        dynamic_cases,
        test_expected.raw_bits,
        test_cfg,
    )

    ramp = full_scale_ramp(cfg, samples_per_code=ramp_samples_per_code)
    ramp_conversion = run_normal_sar_conversion(
        ramp,
        physical_q8,
        cfg,
        chip_id,
        stream_id=630,
        include_random_noise=False,
        stochastic_srm=False,
    )
    static_cases = _static_decode_cases(
        nominal_q8,
        physical_q8,
        self_cal_q8,
        external_q8,
        ramp_conversion,
    )
    static_codes, static_saturation = decode_cases(
        static_cases,
        ramp_conversion.raw_bits,
        cfg,
    )

    metrics, linearity_arrays = _summarize_metrics(
        dynamic_codes,
        static_codes,
        dynamic_saturation,
        static_saturation,
        cfg,
    )
    ideal_control = ideal_quantizer_control(cfg, chip_id)
    srm_noise_ablation, srm_noise_rows = run_srm_noise_reduction_ablation(
        cfg,
        physical_q8,
        self_cal_q8,
        chip_id,
        repeat_count=srm_noise_repeats,
    )

    weight_errors = {
        "nominal_direct_rmse_lsb": direct_weight_rmse_lsb(physical_q8, nominal_q8),
        "self_cal_direct_rmse_lsb": direct_weight_rmse_lsb(physical_q8, self_cal_q8),
        "external_sine_direct_rmse_lsb": direct_weight_rmse_lsb(
            physical_q8, external_q8
        ),
        "nominal_gain_aligned_rmse_lsb": gain_aligned_rmse_lsb(
            physical_q8, nominal_q8
        ),
        "self_cal_gain_aligned_rmse_lsb": gain_aligned_rmse_lsb(
            physical_q8, self_cal_q8
        ),
        "external_sine_gain_aligned_rmse_lsb": gain_aligned_rmse_lsb(
            physical_q8, external_q8
        ),
        "self_cal_gain_alignment_factor": gain_to_align_estimate(
            physical_q8, self_cal_q8
        ),
        "external_sine_gain_alignment_factor": gain_to_align_estimate(
            physical_q8, external_q8
        ),
    }
    weight_errors["self_cal_gain_aligned_improvement_x"] = float(
        weight_errors["nominal_gain_aligned_rmse_lsb"]
        / weight_errors["self_cal_gain_aligned_rmse_lsb"]
    )

    summary = {
        "schema_version": 2,
        "experiment": EXPERIMENT_NAME,
        "algorithm_under_test": {
            "type": "project_on_chip_foreground_self_calibration",
            "output_bits": 16,
            "raw_decisions": cfg.cap_num,
            "trusted_lsb_reference_bits": cfg.max_calib_bit + 1,
            "recursively_calibrated_bits": [cfg.max_calib_bit + 1, cfg.cap_num - 1],
            "pn_pairs_per_target": cfg.avg_loops,
            "scalar_comparator_measurements_per_target": 2 * cfg.avg_loops,
            "top_bit_protection": [cfg.cap_num - 2, cfg.cap_num - 1],
            "weight_format": "signed_Q8",
            "srm_decisions": cfg.srm_decisions,
            "source": "analysis/full_sar_behavioral_20260729/full_sar_model.py",
        },
        "adctoolbox_role": {
            "primary": "FFT and ramp-histogram metrics",
            "secondary": "external sine-fit calibration baseline only",
            "explicitly_not": "the project on-chip self-calibration algorithm",
            "version": version("adctoolbox"),
            "reviewed_commit": REVIEWED_ADCTOOLBOX_COMMIT,
            "module_path": str(Path(adctoolbox.__file__).resolve()),
        },
        "experiment_conditions": {
            "chip_id": chip_id,
            "normal_conversion_random_noise_enabled": False,
            "calibration_comparator_offset_lsb": cfg.calibration_comparator_offset_lsb,
            "calibration_comparator_noise_lsb": cfg.calibration_comparator_noise_lsb,
            "srm_comparator_noise_lsb": cfg.srm_comparator_noise_lsb,
            "unit_cap_sigma_pct": physical_cfg.unit_cap_sigma_pct,
            "node_parasitic_sigma_pct": physical_cfg.node_parasitic_sigma_pct,
            "comparator_input_sigma_pct": physical_cfg.comparator_input_sigma_pct,
            "n_fft": cfg.n_fft,
            "train_fin_hz": train_fin_hz,
            "train_fft_bin": train_bin,
            "test_fin_hz": test_fin_hz,
            "test_fft_bin": test_bin,
            "ramp_samples_per_code": ramp_samples_per_code,
            "ramp_sample_count": len(ramp),
            "actual_chip_mismatch": {
                "bit_cap_rel_error_pct_rms": float(
                    100.0 * np.sqrt(np.mean(np.asarray(chip.cap_rel_error) ** 2))
                ),
                "bit_cap_rel_error_pct_min": float(100.0 * np.min(chip.cap_rel_error)),
                "bit_cap_rel_error_pct_max": float(100.0 * np.max(chip.cap_rel_error)),
                "bridge_rel_error_pct_rms": float(
                    100.0 * np.sqrt(np.mean(np.asarray(chip.bridge_rel_error) ** 2))
                ),
                "effective_weight_rel_error_pct_rms": float(
                    100.0
                    * np.sqrt(np.mean(np.asarray(chip.effective_weight_rel_error) ** 2))
                ),
                "effective_weight_rel_error_pct_min": float(
                    100.0 * np.min(chip.effective_weight_rel_error)
                ),
                "effective_weight_rel_error_pct_max": float(
                    100.0 * np.max(chip.effective_weight_rel_error)
                ),
            },
        },
        "ideal_16bit_control": ideal_control,
        "srm_noise_reduction_ablation": srm_noise_ablation,
        "weight_errors": weight_errors,
        "decoder_metrics": metrics,
        "external_sine_baseline": {
            "classification": "external_foreground_fit_not_on_chip_self_cal",
            "fit": external_result,
            "diagnostic": external_diagnostic,
        },
        "self_calibration_trace_summary": {
            "target_count": len(calibration_trace),
            "first_target": int(calibration_trace[0]["target_bit"]),
            "last_target": int(calibration_trace[-1]["target_bit"]),
        },
        "primary_result_deltas": {
            "self_cal_no_srm_sndr_gain_db": float(
                metrics["SELF_CAL_Q8_NO_SRM"]["sndr_db"]
                - metrics["NOMINAL_Q8_NO_SRM"]["sndr_db"]
            ),
            "self_cal_expected_srm_sndr_gain_db": float(
                metrics["SELF_CAL_Q8_SRM_EXPECTED"]["sndr_db"]
                - metrics["NOMINAL_Q8_NO_SRM"]["sndr_db"]
            ),
            "expected_srm_increment_over_self_cal_db": float(
                metrics["SELF_CAL_Q8_SRM_EXPECTED"]["sndr_db"]
                - metrics["SELF_CAL_Q8_NO_SRM"]["sndr_db"]
            ),
            "stochastic_srm_penalty_vs_expected_db": float(
                metrics["SELF_CAL_Q8_SRM_22_STOCHASTIC"]["sndr_db"]
                - metrics["SELF_CAL_Q8_SRM_EXPECTED"]["sndr_db"]
            ),
            "oracle_residue_information_gain_db": float(
                metrics["ORACLE_Q8_SRM_EXPECTED"]["sndr_db"]
                - metrics["ORACLE_Q8_NO_SRM"]["sndr_db"]
            ),
            "self_cal_gap_to_oracle_without_srm_db": float(
                metrics["SELF_CAL_Q8_NO_SRM"]["sndr_db"]
                - metrics["ORACLE_Q8_NO_SRM"]["sndr_db"]
            ),
            "self_cal_gap_to_oracle_with_expected_srm_db": float(
                metrics["SELF_CAL_Q8_SRM_EXPECTED"]["sndr_db"]
                - metrics["ORACLE_Q8_SRM_EXPECTED"]["sndr_db"]
            ),
            "nominal_exact_residue_increment_db": float(
                metrics["NOMINAL_Q8_EXACT_RESIDUE"]["sndr_db"]
                - metrics["NOMINAL_Q8_NO_SRM"]["sndr_db"]
            ),
            "self_cal_exact_residue_increment_db": float(
                metrics["SELF_CAL_Q8_EXACT_RESIDUE"]["sndr_db"]
                - metrics["SELF_CAL_Q8_NO_SRM"]["sndr_db"]
            ),
        },
        "evidence_boundary": [
            "Behavioral physical-CDAC proxy, not transistor or PEX simulation.",
            "Normal conversion random noise is disabled to isolate mismatch correction.",
            (
                "The separate paired SRM noise ablation enables comparator noise and "
                "shares one raw-bit stream between SRM on/off decoders."
            ),
            (
                "The SRM noise ablation does not reproduce split-sampling, AZ aliasing, "
                "or the complete paper noise budget."
            ),
            (
                "ADCToolbox sine fitting requires an external coherent tone "
                "and is not self-calibration."
            ),
        ],
    }

    _write_metrics_csv(output_dir / "metrics.csv", metrics)
    _write_weights_csv(
        output_dir / "weights.csv",
        nominal_q8,
        physical_q8,
        self_cal_q8,
        external_q8,
    )
    _write_srm_noise_ablation_csv(
        output_dir / "srm_noise_ablation.csv",
        srm_noise_rows,
    )
    (output_dir / "calibration_trace.json").write_text(
        json.dumps(_json_ready(calibration_trace), indent=2, ensure_ascii=True),
        encoding="utf-8",
    )
    (output_dir / "summary.json").write_text(
        json.dumps(_json_ready(summary), indent=2, ensure_ascii=True),
        encoding="utf-8",
    )

    _plot_weight_error(
        output_dir / "fig_weight_error.png",
        physical_q8,
        nominal_q8,
        self_cal_q8,
        external_q8,
    )
    _plot_spectrum(output_dir / "fig_spectrum_compare.png", dynamic_codes, cfg)
    _plot_linearity(output_dir / "fig_inl_compare.png", linearity_arrays)
    _plot_calibration_trace(
        output_dir / "fig_calibration_trace.png",
        calibration_trace,
    )
    _plot_srm_noise_ablation(
        output_dir / "fig_srm_noise_ablation.png",
        srm_noise_rows,
    )
    return summary


def _print_summary(summary: Mapping[str, Any]) -> None:
    print("=== 16-bit on-chip self-calibration experiment ===")
    print("Primary algorithm: project P/N recursive foreground self-calibration")
    print("ADCToolbox role: metrics plus external sine-fit comparison only")
    control = summary["ideal_16bit_control"]
    print(
        "Ideal 16-bit control: "
        f"SNDR={control['sndr_db']:.3f} dB, "
        f"theory={control['theoretical_full_scale_sndr_db']:.3f} dB"
    )
    for decoder, values in summary["decoder_metrics"].items():
        print(
            f"{decoder:38s} "
            f"SNDR={values['sndr_db']:8.3f} dB  "
            f"SFDR={values['sfdr_db']:8.3f} dB  "
            f"INLpp={values['inl_pp_lsb']:8.3f} LSB  "
            f"missing={values['missing_codes']:4d}"
        )
    errors = summary["weight_errors"]
    print(
        "Gain-aligned weight RMSE: "
        f"nominal={errors['nominal_gain_aligned_rmse_lsb']:.4f} LSB, "
        f"self-cal={errors['self_cal_gain_aligned_rmse_lsb']:.4f} LSB, "
        f"external-sine={errors['external_sine_gain_aligned_rmse_lsb']:.4f} LSB"
    )
    ablation = summary["srm_noise_reduction_ablation"]
    paired = ablation["paired_improvement"]
    oracle = ablation["decoder_metrics"]
    print(
        "Paired noisy SRM ablation: "
        f"oracle {oracle['ORACLE_NO_SRM_NOISY']['sndr_db']['mean']:.3f} -> "
        f"{oracle['ORACLE_SRM_22_NOISY']['sndr_db']['mean']:.3f} dB "
        f"(mean gain {paired['oracle_sndr_gain_db']['mean']:.3f} dB); "
        f"self-cal mean gain {paired['self_cal_sndr_gain_db']['mean']:.3f} dB"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parent / "outputs",
        help="Output directory.",
    )
    parser.add_argument("--chip-id", type=int, default=17)
    parser.add_argument("--n-fft", type=int, default=16384)
    parser.add_argument("--ramp-samples-per-code", type=int, default=2)
    parser.add_argument("--srm-noise-repeats", type=int, default=32)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    summary = run_experiment(
        output_dir=args.output.resolve(),
        chip_id=args.chip_id,
        n_fft=args.n_fft,
        ramp_samples_per_code=args.ramp_samples_per_code,
        srm_noise_repeats=args.srm_noise_repeats,
    )
    _print_summary(summary)
    print(f"Outputs: {args.output.resolve()}")


if __name__ == "__main__":
    main()

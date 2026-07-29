"""Complete behavioral loop for the active 20-decision SAR ADC project.

The algorithmic source of truth remains the local RTL:

* ``rtl/sar_calib_ctrl_serial.sv`` for recursive foreground calibration;
* ``rtl/srm_residue_estimator.sv`` for the 22-decision SRM count-to-Q8 LUT;
* ``rtl/sar_reconstruction.sv`` for signed Q8 reconstruction and saturation.

ADCToolbox is used only for standardized spectrum and ramp-histogram metrics.
The analog path in this module is a system-level differential CDAC/residue
model. It is not a transistor, PVT, extracted-parasitic, or reference-network
signoff model.
"""

from __future__ import annotations

import math
from dataclasses import asdict, dataclass
from typing import Dict, Iterable, List, Sequence, Tuple

import numpy as np
from scipy.special import ndtr

try:
    import adctoolbox
except ImportError as exc:  # pragma: no cover - deployment guard
    raise RuntimeError(
        "ADCToolbox 0.9.1 is required. Install the pinned dependency from "
        "requirements.txt before running this campaign."
    ) from exc


# Local RTL order is LSB first: index 0 is the trusted unit-weight decision.
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

# Bit-exact Q8 lookup table from rtl/srm_residue_estimator.sv.
SRM_LUT_Q8 = np.array(
    [
        -258,
        -194,
        -158,
        -131,
        -110,
        -91,
        -74,
        -58,
        -43,
        -28,
        -14,
        0,
        14,
        28,
        43,
        58,
        74,
        91,
        110,
        131,
        158,
        194,
        258,
    ],
    dtype=np.int64,
)

DECODER_ORDER = (
    "NOMINAL_NO_SRM",
    "CAL_NO_SRM",
    "CAL_SRM",
    "ORACLE_SRM",
)


@dataclass(frozen=True)
class FullSarConfig:
    """Configuration for one complete behavioral campaign."""

    cap_num: int = 20
    output_bits: int = 16
    frac_bits: int = 8
    max_calib_bit: int = 5
    avg_loops: int = 32
    srm_decisions: int = 22
    seed: int = 20260729

    n_chips: int = 512
    n_fft: int = 8192
    fs_hz: float = 5.0e6
    fin_target_hz: float = 1.0e6
    sine_amplitude_code: float = 0.82 * 32767.0
    static_samples_per_code: int = 2
    representative_samples_per_code: int = 8

    # Manufacturing model follows the current calibration TB split.
    low_weight_mismatch_sigma: float = 0.0015
    high_weight_mismatch_sigma: float = 0.0300

    # Foreground calibration comparator settings, in final-code LSB.
    calibration_comparator_offset_lsb: float = 5.0
    calibration_comparator_noise_lsb: float = 0.50

    # Normal conversion non-idealities, in final-code LSB unless noted.
    sampling_noise_lsb: float = 0.35
    normal_comparator_noise_lsb: float = 0.30
    normal_comparator_offset_lsb: float = 0.00
    reference_noise_rms_fraction: float = 0.0
    dac_settling_error_fraction: float = 0.0

    # The RTL SRM LUT is qualified for sigma = 0.5 final-code LSB.
    srm_comparator_noise_lsb: float = 0.50
    srm_comparator_offset_lsb: float = 0.0

    def validate(self) -> None:
        if self.cap_num != 20:
            raise ValueError("The active RTL and weight contract require cap_num=20.")
        if self.output_bits != 16 or self.frac_bits != 8:
            raise ValueError("The active fixed-point contract requires signed-16/Q8.")
        if self.srm_decisions != 22:
            raise ValueError("The active SRM LUT is qualified for exactly 22 decisions.")
        if self.avg_loops < 1 or self.avg_loops & (self.avg_loops - 1):
            raise ValueError("avg_loops must be a positive power of two.")
        if self.static_samples_per_code < 1:
            raise ValueError("static_samples_per_code must be positive.")
        if len(IDEAL_WEIGHT_LSB) != self.cap_num:
            raise ValueError("Weight-table length does not match cap_num.")


@dataclass
class ConversionResult:
    """Raw normal-conversion state shared by all digital decoders."""

    raw_bits: np.ndarray
    physical_residue_q8: np.ndarray
    srm_ones_count: np.ndarray
    srm_residue_q8: np.ndarray


@dataclass
class DecoderMetrics:
    chip_id: int
    decoder: str
    dynamic_sndr_db: float
    dynamic_snr_db: float
    dynamic_sfdr_db: float
    dynamic_thd_db: float
    dynamic_enob: float
    dnl_min_lsb: float
    dnl_max_lsb: float
    dnl_pp_lsb: float
    inl_min_lsb: float
    inl_max_lsb: float
    inl_pp_lsb: float
    missing_codes: int
    saturation_fraction: float
    weight_rmse_gain_aligned_lsb: float
    srm_nonzero_fraction: float
    srm_count_mean: float


def stable_rng(cfg: FullSarConfig, *items: int) -> np.random.Generator:
    """Return a process-stable RNG stream for one model concern."""

    return np.random.default_rng(np.random.SeedSequence([cfg.seed, *map(int, items)]))


def ideal_weight_q8(cfg: FullSarConfig) -> np.ndarray:
    return np.rint(IDEAL_WEIGHT_LSB * (1 << cfg.frac_bits)).astype(np.int64)


def manufacture_chip_q8(cfg: FullSarConfig, chip_id: int) -> np.ndarray:
    """Create one deterministic physical effective-weight realization."""

    rng = stable_rng(cfg, 100, chip_id)
    nominal = ideal_weight_q8(cfg).astype(float)
    sigma = np.full(cfg.cap_num, cfg.high_weight_mismatch_sigma, dtype=float)
    sigma[: cfg.max_calib_bit + 1] = cfg.low_weight_mismatch_sigma
    return nominal * (1.0 + rng.normal(0.0, sigma))


def bits_to_word(bits: Sequence[bool]) -> int:
    word = 0
    for index, value in enumerate(bits):
        if value:
            word |= 1 << index
    return word


def _protect_code(
    sar_code: np.ndarray,
    target_bit: int,
    cfg: FullSarConfig,
) -> np.ndarray:
    protected = np.array(sar_code, dtype=bool, copy=True)
    protect_start = cfg.cap_num - 2
    protect_low = cfg.cap_num - 3
    if target_bit == protect_start:
        protected[protect_low] = True
    elif target_bit == cfg.cap_num - 1:
        protected[protect_start] = True
        protected[protect_low] = True
    return protected


def _calibration_comparator_decision(
    dac_p_force: np.ndarray,
    dac_n_force: np.ndarray,
    physical_q8: np.ndarray,
    cfg: FullSarConfig,
    rng: np.random.Generator,
) -> bool:
    vp = float(np.sum(physical_q8[dac_p_force]))
    vn = float(np.sum(physical_q8[dac_n_force]))
    q8 = float(1 << cfg.frac_bits)
    offset = cfg.calibration_comparator_offset_lsb * q8
    noise = cfg.calibration_comparator_noise_lsb * q8 * rng.normal()
    return (vp - vn + offset + noise) > 0.0


def _rtl_phase_search(
    target_bit: int,
    phase: str,
    shadow_q8: np.ndarray,
    physical_q8: np.ndarray,
    cfg: FullSarConfig,
    rng: np.random.Generator,
) -> Tuple[np.ndarray, int]:
    """Mirror one P/N phase of sar_calib_ctrl_serial.sv."""

    sar_code = np.zeros(cfg.cap_num, dtype=bool)
    protect_search_top = cfg.cap_num - 4
    sar_ptr = protect_search_top if target_bit >= cfg.cap_num - 2 else target_bit - 1

    while True:
        sar_code[sar_ptr] = True
        target_drive = np.zeros(cfg.cap_num, dtype=bool)
        target_drive[target_bit] = True
        protected = _protect_code(sar_code, target_bit, cfg)

        if phase == "P":
            comp_out = _calibration_comparator_decision(
                target_drive, protected, physical_q8, cfg, rng
            )
            if not comp_out:
                sar_code[sar_ptr] = False
        elif phase == "N":
            comp_out = _calibration_comparator_decision(
                protected, target_drive, physical_q8, cfg, rng
            )
            if comp_out:
                sar_code[sar_ptr] = False
        else:
            raise ValueError(f"Unsupported calibration phase {phase!r}.")

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


def run_rtl_equivalent_calibration(
    physical_q8: np.ndarray,
    cfg: FullSarConfig,
    chip_id: int,
) -> Tuple[np.ndarray, List[Dict[str, object]]]:
    """Run the local foreground-calibration FSM in behavioral form."""

    rng = stable_rng(cfg, 200, chip_id)
    shadow = np.zeros(cfg.cap_num, dtype=np.int64)
    for bit in range(cfg.max_calib_bit + 1):
        shadow[bit] = 1 << (cfg.frac_bits + bit)

    avg_shift = int(math.log2(cfg.avg_loops))
    trace: List[Dict[str, object]] = []
    for target in range(cfg.max_calib_bit + 1, cfg.cap_num):
        accumulator = 0
        first_record: Dict[str, int] | None = None
        last_record: Dict[str, int] | None = None
        for _ in range(cfg.avg_loops):
            p_code, meas_p = _rtl_phase_search(
                target, "P", shadow, physical_q8, cfg, rng
            )
            n_code, meas_n = _rtl_phase_search(
                target, "N", shadow, physical_q8, cfg, rng
            )
            accumulator += meas_p + meas_n
            record = {
                "p_code": bits_to_word(p_code),
                "n_code": bits_to_word(n_code),
                "meas_p_q8": meas_p,
                "meas_n_q8": meas_n,
            }
            first_record = record if first_record is None else first_record
            last_record = record

        result_q8 = int((accumulator + (1 << avg_shift)) >> (avg_shift + 1))
        shadow[target] = result_q8
        trace.append(
            {
                "target_bit": target,
                "result_q8": result_q8,
                "result_lsb": result_q8 / float(1 << cfg.frac_bits),
                "physical_lsb": float(physical_q8[target] / (1 << cfg.frac_bits)),
                "first_phase": first_record,
                "last_phase": last_record,
            }
        )
    return shadow, trace


def coherent_sine(
    cfg: FullSarConfig,
    chip_id: int,
) -> Tuple[np.ndarray, float, int]:
    """Generate a coherent input with optional aperture jitter."""

    k = int(round(cfg.fin_target_hz / cfg.fs_hz * cfg.n_fft))
    k = max(1, min(k, cfg.n_fft // 2 - 1))
    while math.gcd(k, cfg.n_fft) != 1 and k + 1 < cfg.n_fft // 2:
        k += 1
    fin = cfg.fs_hz * k / cfg.n_fft
    n = np.arange(cfg.n_fft, dtype=float)
    phase = 2.0 * np.pi * k * n / cfg.n_fft
    # A deterministic per-chip phase avoids a single phase relation becoming
    # a hidden Monte-Carlo constant while retaining coherent sampling.
    phase += float(stable_rng(cfg, 300, chip_id).uniform(0.0, 2.0 * np.pi))
    return cfg.sine_amplitude_code * np.sin(phase), fin, k


def full_scale_ramp(cfg: FullSarConfig, samples_per_code: int | None = None) -> np.ndarray:
    """Generate a uniform full-range signed-code ramp for code-density analysis."""

    spc = cfg.static_samples_per_code if samples_per_code is None else samples_per_code
    code_count = 1 << cfg.output_bits
    sample_count = code_count * spc
    min_code = -(1 << (cfg.output_bits - 1))
    max_code = (1 << (cfg.output_bits - 1)) - 1
    return np.linspace(
        min_code - 0.5,
        max_code + 0.5,
        sample_count,
        endpoint=False,
        dtype=float,
    ) + 0.5 / spc


def run_normal_sar_conversion(
    input_codes: np.ndarray,
    physical_q8: np.ndarray,
    cfg: FullSarConfig,
    chip_id: int,
    stream_id: int,
    include_random_noise: bool = True,
    stochastic_srm: bool = True,
) -> ConversionResult:
    """Run sampling, 20 signed SAR decisions, residue observation, and SRM.

    ``input_codes`` is the desired signed 16-bit input-domain value. The
    differential CDAC target is twice this value because the reconstruction
    RTL uses a two-sided ``+W/-W`` sum followed by ``/2``.
    """

    values = np.asarray(input_codes, dtype=float)
    rng = stable_rng(cfg, 400, chip_id, stream_id)
    q8 = float(1 << cfg.frac_bits)

    sampled = values.copy()
    if include_random_noise and cfg.sampling_noise_lsb > 0.0:
        sampled += cfg.sampling_noise_lsb * rng.standard_normal(values.shape)
    target_q8 = sampled * (2.0 * q8)

    if include_random_noise and cfg.reference_noise_rms_fraction > 0.0:
        reference_gain = 1.0 + cfg.reference_noise_rms_fraction * rng.standard_normal(
            values.shape
        )
    else:
        reference_gain = 1.0

    analog_sum_q8 = np.zeros(values.shape, dtype=float)
    bits = np.zeros(values.shape + (cfg.cap_num,), dtype=np.int8)
    for bit in range(cfg.cap_num - 1, -1, -1):
        comparator_noise = (
            2.0
            * q8
            * cfg.normal_comparator_noise_lsb
            * rng.standard_normal(values.shape)
            if include_random_noise and cfg.normal_comparator_noise_lsb > 0.0
            else 0.0
        )
        comparator_offset = 2.0 * q8 * cfg.normal_comparator_offset_lsb
        choose_plus = (
            target_q8 - analog_sum_q8 + comparator_offset + comparator_noise
        ) >= 0.0
        bits[..., bit] = choose_plus.astype(np.int8)

        # A constant fractional settling shortfall is an explicit optional
        # system-level hook. The qualified default is zero.
        settled_weight = physical_q8[bit] * (1.0 - cfg.dac_settling_error_fraction)
        step = settled_weight * reference_gain
        analog_sum_q8 += np.where(choose_plus, step, -step)

    physical_residue_q8 = (target_q8 - analog_sum_q8) / 2.0
    sigma_q8 = cfg.srm_comparator_noise_lsb * q8
    if sigma_q8 <= 0.0:
        raise ValueError("srm_comparator_noise_lsb must be positive for the RTL LUT.")
    z_score = (physical_residue_q8 + cfg.srm_comparator_offset_lsb * q8) / sigma_q8
    one_probability = np.clip(ndtr(z_score), 0.0, 1.0)
    if stochastic_srm:
        # A binomial count is statistically identical to accepting 22
        # independent decision_valid pulses and is substantially faster for
        # the 512-chip dynamic run.
        ones_count = rng.binomial(cfg.srm_decisions, one_probability).astype(np.int8)
    else:
        # Static INL/DNL must characterize the deterministic transfer curve.
        # Rounding the expected count removes Monte-Carlo empty-bin artifacts
        # while preserving the exact RTL count-to-LUT quantization.
        ones_count = np.rint(cfg.srm_decisions * one_probability).astype(np.int8)
    srm_q8 = SRM_LUT_Q8[ones_count]
    return ConversionResult(
        raw_bits=bits,
        physical_residue_q8=physical_residue_q8,
        srm_ones_count=ones_count,
        srm_residue_q8=srm_q8,
    )


def rtl_reconstruct(
    bits: np.ndarray,
    weights_q8: np.ndarray,
    cfg: FullSarConfig,
    residue_q8: np.ndarray | int,
) -> Tuple[np.ndarray, float]:
    """Mirror sar_reconstruction.sv with signed integer Q8 arithmetic."""

    sign = bits.astype(np.int64) * 2 - 1
    weighted_sum = sign @ np.rint(weights_q8).astype(np.int64)
    normalized = (weighted_sum >> 1) + np.asarray(residue_q8, dtype=np.int64)
    rounded = normalized + (1 << (cfg.frac_bits - 1))
    shifted = rounded >> cfg.frac_bits
    min_code = -(1 << (cfg.output_bits - 1))
    max_code = (1 << (cfg.output_bits - 1)) - 1
    saturated = (shifted < min_code) | (shifted > max_code)
    return np.clip(shifted, min_code, max_code).astype(np.int32), float(
        np.mean(saturated)
    )


def decoder_weights(
    cfg: FullSarConfig,
    physical_q8: np.ndarray,
    calibrated_q8: np.ndarray,
) -> Dict[str, Tuple[np.ndarray, bool]]:
    nominal = ideal_weight_q8(cfg)
    return {
        "NOMINAL_NO_SRM": (nominal, False),
        "CAL_NO_SRM": (calibrated_q8, False),
        "CAL_SRM": (calibrated_q8, True),
        "ORACLE_SRM": (physical_q8, True),
    }


def _best_gain_aligned_rmse(reference: np.ndarray, estimate: np.ndarray) -> float:
    denominator = float(np.dot(estimate, estimate))
    gain = float(np.dot(reference, estimate) / denominator) if denominator > 0.0 else 1.0
    error = gain * estimate - reference
    return float(np.sqrt(np.mean(error**2)))


def spectrum_metrics(codes: np.ndarray, cfg: FullSarConfig) -> Dict[str, float]:
    """Use ADCToolbox's standardized coherent-spectrum implementation."""

    result = adctoolbox.analyze_spectrum(
        np.asarray(codes, dtype=float),
        fs=cfg.fs_hz,
        win_type="rectangular",
        side_bin=0,
        max_harmonic=8,
        create_plot=False,
    )
    return {
        "sndr_db": float(result["sndr_dbc"]),
        "snr_db": float(result["snr_dbc"]),
        "sfdr_db": float(result["sfdr_dbc"]),
        "thd_db": float(result["thd_dbc"]),
        "enob": float(result["enob"]),
    }


def linearity_metrics(codes: np.ndarray, cfg: FullSarConfig) -> Dict[str, object]:
    """Use ADCToolbox's ramp-histogram INL/DNL implementation."""

    hardware_min = -(1 << (cfg.output_bits - 1))
    hardware_max = (1 << (cfg.output_bits - 1)) - 1
    # Static INL/DNL excludes ADC gain and offset by analyzing the exercised
    # code span and applying endpoint correction. Counting unexercised rail
    # codes as missing would incorrectly turn global gain error into DNL.
    min_code = max(hardware_min, int(np.min(codes)))
    max_code = min(hardware_max, int(np.max(codes)))
    if max_code - min_code < 3:
        raise ValueError("Ramp exercised too few output codes for INL/DNL analysis.")
    result = adctoolbox.analyze_inl_from_ramp(
        np.asarray(codes, dtype=np.int32),
        num_bits=None,
        code_min=min_code,
        code_max=max_code,
        input_type="codes",
        endpoint="endpoints",
        exclude_endpoints=True,
        create_plot=False,
    )
    return {
        "dnl_min_lsb": float(result["dnl_min"]),
        "dnl_max_lsb": float(result["dnl_max"]),
        "dnl_pp_lsb": float(result["dnl_pp"]),
        "inl_min_lsb": float(result["inl_min"]),
        "inl_max_lsb": float(result["inl_max"]),
        "inl_pp_lsb": float(result["inl_pp"]),
        "missing_codes": int(len(result["missing_codes"])),
        "code": np.asarray(result["code"]),
        "dnl": np.asarray(result["dnl"]),
        "transition_code": np.asarray(result["transition_code"]),
        "inl": np.asarray(result["inl"]),
    }


def evaluate_chip(
    chip_id: int,
    cfg: FullSarConfig,
    static_samples_per_code: int | None = None,
    retain_linearity_arrays: bool = False,
) -> Tuple[List[DecoderMetrics], Dict[str, object]]:
    """Execute calibration plus dynamic/static full-loop tests for one chip."""

    cfg.validate()
    physical_q8 = manufacture_chip_q8(cfg, chip_id)
    calibrated_q8, calibration_trace = run_rtl_equivalent_calibration(
        physical_q8, cfg, chip_id
    )

    sine_input, fin_hz, fft_bin = coherent_sine(cfg, chip_id)
    ramp_input = full_scale_ramp(cfg, samples_per_code=static_samples_per_code)
    sine_conversion = run_normal_sar_conversion(
        sine_input, physical_q8, cfg, chip_id, stream_id=1
    )
    ramp_conversion = run_normal_sar_conversion(
        ramp_input,
        physical_q8,
        cfg,
        chip_id,
        stream_id=2,
        include_random_noise=False,
        stochastic_srm=False,
    )

    results: List[DecoderMetrics] = []
    retained: Dict[str, object] = {}
    for name in DECODER_ORDER:
        weights_q8, use_srm = decoder_weights(cfg, physical_q8, calibrated_q8)[name]
        sine_residue = sine_conversion.srm_residue_q8 if use_srm else 0
        ramp_residue = ramp_conversion.srm_residue_q8 if use_srm else 0
        sine_codes, sine_sat = rtl_reconstruct(
            sine_conversion.raw_bits, weights_q8, cfg, sine_residue
        )
        ramp_codes, ramp_sat = rtl_reconstruct(
            ramp_conversion.raw_bits, weights_q8, cfg, ramp_residue
        )

        dynamic = spectrum_metrics(sine_codes, cfg)
        static = linearity_metrics(ramp_codes, cfg)
        rmse = _best_gain_aligned_rmse(
            physical_q8 / float(1 << cfg.frac_bits),
            np.asarray(weights_q8, dtype=float) / float(1 << cfg.frac_bits),
        )
        results.append(
            DecoderMetrics(
                chip_id=chip_id,
                decoder=name,
                dynamic_sndr_db=dynamic["sndr_db"],
                dynamic_snr_db=dynamic["snr_db"],
                dynamic_sfdr_db=dynamic["sfdr_db"],
                dynamic_thd_db=dynamic["thd_db"],
                dynamic_enob=dynamic["enob"],
                dnl_min_lsb=float(static["dnl_min_lsb"]),
                dnl_max_lsb=float(static["dnl_max_lsb"]),
                dnl_pp_lsb=float(static["dnl_pp_lsb"]),
                inl_min_lsb=float(static["inl_min_lsb"]),
                inl_max_lsb=float(static["inl_max_lsb"]),
                inl_pp_lsb=float(static["inl_pp_lsb"]),
                missing_codes=int(static["missing_codes"]),
                saturation_fraction=max(sine_sat, ramp_sat),
                weight_rmse_gain_aligned_lsb=rmse,
                srm_nonzero_fraction=float(
                    np.mean(sine_conversion.srm_residue_q8 != 0)
                ),
                srm_count_mean=float(np.mean(sine_conversion.srm_ones_count)),
            )
        )
        if retain_linearity_arrays:
            retained[name] = {
                "sine_codes": sine_codes,
                "ramp_codes": ramp_codes,
                "linearity": {
                    "code": static["code"],
                    "dnl": static["dnl"],
                    "transition_code": static["transition_code"],
                    "inl": static["inl"],
                },
            }

    trace = {
        "chip_id": chip_id,
        "config": asdict(cfg),
        "fin_hz": fin_hz,
        "fft_bin": fft_bin,
        "physical_weights_lsb": (
            physical_q8 / float(1 << cfg.frac_bits)
        ).tolist(),
        "calibrated_weights_lsb": (
            calibrated_q8 / float(1 << cfg.frac_bits)
        ).tolist(),
        "calibration_trace": calibration_trace,
        "srm": {
            "decision_count": cfg.srm_decisions,
            "lut_q8": SRM_LUT_Q8.tolist(),
            "sine_count_histogram": np.bincount(
                sine_conversion.srm_ones_count, minlength=23
            ).tolist(),
            "sine_residue_rmse_q8": float(
                np.sqrt(
                    np.mean(
                        (
                            sine_conversion.srm_residue_q8
                            - sine_conversion.physical_residue_q8
                        )
                        ** 2
                    )
                )
            ),
        },
        "retained": retained,
    }
    return results, trace


def summarize(values: Iterable[float]) -> Dict[str, float]:
    data = np.asarray(list(values), dtype=float)
    return {
        "mean": float(np.mean(data)),
        "std": float(np.std(data, ddof=1)) if len(data) > 1 else 0.0,
        "min": float(np.min(data)),
        "p01": float(np.percentile(data, 1)),
        "p05": float(np.percentile(data, 5)),
        "median": float(np.percentile(data, 50)),
        "p95": float(np.percentile(data, 95)),
        "p99": float(np.percentile(data, 99)),
        "max": float(np.max(data)),
    }


def metrics_to_dict(metric: DecoderMetrics) -> Dict[str, object]:
    return asdict(metric)

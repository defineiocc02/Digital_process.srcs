"""Regression tests for the 16-bit self-calibration integration experiment."""

from __future__ import annotations

from pathlib import Path
import sys

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from analysis.full_sar_behavioral_20260729.full_sar_model import (
    run_normal_sar_conversion,
    run_rtl_equivalent_calibration,
)
from analysis.physical_cdac_mismatch_20260729.physical_cdac import (
    PhysicalCdacConfig,
    draw_physical_chip,
    nominal_weights_q8,
)
from analysis.self_cal_adctoolbox_behavioral_20260830.run_self_cal_behavioral import (
    EXTERNAL_BASELINE,
    gain_aligned_rmse_lsb,
    make_self_cal_config,
    run_external_sine_baseline,
    run_srm_noise_reduction_ablation,
)


def test_active_contract_is_16bit_recursive_self_calibration() -> None:
    cfg = make_self_cal_config(n_fft=1024)
    assert cfg.output_bits == 16
    assert cfg.cap_num == 20
    assert cfg.frac_bits == 8
    assert cfg.max_calib_bit == 5
    assert cfg.avg_loops == 32
    assert cfg.srm_decisions == 22


def test_project_self_cal_reduces_weight_error_for_reference_chip() -> None:
    cfg = make_self_cal_config(n_fft=1024)
    physical_cfg = PhysicalCdacConfig()
    chip = draw_physical_chip(physical_cfg, chip_id=17)
    nominal_q8 = nominal_weights_q8(physical_cfg)
    calibrated_q8, trace = run_rtl_equivalent_calibration(chip.weights_q8, cfg, 17)

    assert [record["target_bit"] for record in trace] == list(range(6, 20))
    assert gain_aligned_rmse_lsb(chip.weights_q8, calibrated_q8) < gain_aligned_rmse_lsb(
        chip.weights_q8, nominal_q8
    )


def test_srm_sampling_does_not_change_normal_sar_bits() -> None:
    cfg = make_self_cal_config(n_fft=1024)
    chip = draw_physical_chip(PhysicalCdacConfig(), chip_id=17)
    input_codes = np.linspace(-30000.0, 30000.0, 257)
    expected = run_normal_sar_conversion(
        input_codes,
        chip.weights_q8,
        cfg,
        chip_id=17,
        stream_id=901,
        include_random_noise=False,
        stochastic_srm=False,
    )
    stochastic = run_normal_sar_conversion(
        input_codes,
        chip.weights_q8,
        cfg,
        chip_id=17,
        stream_id=901,
        include_random_noise=False,
        stochastic_srm=True,
    )
    assert np.array_equal(expected.raw_bits, stochastic.raw_bits)
    assert expected.raw_bits.shape == (257, 20)


def test_adctoolbox_solver_is_an_explicit_external_baseline() -> None:
    cfg = make_self_cal_config(n_fft=2048)
    physical_cfg = PhysicalCdacConfig()
    chip = draw_physical_chip(physical_cfg, chip_id=17)
    nominal_q8 = nominal_weights_q8(physical_cfg)

    phase = 2.0 * np.pi * 293.0 * np.arange(cfg.n_fft) / cfg.n_fft
    input_codes = cfg.sine_amplitude_code * np.sin(phase)
    conversion = run_normal_sar_conversion(
        input_codes,
        chip.weights_q8,
        cfg,
        chip_id=17,
        stream_id=902,
        include_random_noise=False,
        stochastic_srm=False,
    )
    weights, result, diagnostic = run_external_sine_baseline(
        conversion.raw_bits,
        normalized_frequency=293.0 / cfg.n_fft,
        nominal_q8=nominal_q8,
    )

    assert EXTERNAL_BASELINE == "ADCTOOLBOX_SINE_EXTERNAL_BASELINE"
    assert weights.shape == (20,)
    assert np.all(np.isfinite(weights))
    assert diagnostic["shape"] == [cfg.n_fft, 20]
    assert result["scale_convention"] == "adc_reference_scale"


def test_paired_noisy_srm_ablation_reduces_error_without_changing_raw_bits() -> None:
    cfg = make_self_cal_config(n_fft=2048)
    chip = draw_physical_chip(PhysicalCdacConfig(), chip_id=17)
    calibrated_q8, _ = run_rtl_equivalent_calibration(chip.weights_q8, cfg, 17)

    summary, rows = run_srm_noise_reduction_ablation(
        cfg,
        chip.weights_q8,
        calibrated_q8,
        chip_id=17,
        repeat_count=8,
    )

    paired = summary["paired_improvement"]
    assert summary["raw_bits_shared_between_srm_on_off"] is True
    assert len(rows) == 8 * 5
    assert paired["oracle_sndr_gain_db"]["mean"] > 0.0
    assert paired["self_cal_sndr_gain_db"]["mean"] > 0.0
    assert paired["oracle_error_rmse_reduction_ratio"]["mean"] > 1.0
    assert paired["self_cal_error_rmse_reduction_ratio"]["mean"] > 1.0

"""Focused tests for the mismatch-only validation harness."""

from dataclasses import replace

import numpy as np

from analysis.full_sar_behavioral_20260729.full_sar_model import FullSarConfig
from analysis.mismatch_only_noiseless_20260729.run_mismatch_only import (
    _affine_error,
    noiseless_config,
)


def test_noiseless_config_disables_normal_conversion_noise() -> None:
    cfg = noiseless_config(2)
    assert cfg.sampling_noise_lsb == 0.0
    assert cfg.normal_comparator_noise_lsb == 0.0
    assert cfg.normal_comparator_offset_lsb == 0.0
    assert cfg.reference_noise_rms_fraction == 0.0
    assert cfg.dac_settling_error_fraction == 0.0


def test_affine_error_removes_gain_and_offset_only() -> None:
    reference = np.arange(-16.0, 16.0)
    estimate = 0.8 * reference + 3.0
    raw_rmse, aligned_rmse, aligned_max, gain = _affine_error(reference, estimate)
    assert raw_rmse > 1.0
    assert aligned_rmse < 1e-12
    assert aligned_max < 1e-12
    assert abs(gain - 1.25) < 1e-12


def test_default_contract_is_20_decision_signed16_q8() -> None:
    cfg = replace(FullSarConfig(), n_chips=1)
    assert cfg.cap_num == 20
    assert cfg.output_bits == 16
    assert cfg.frac_bits == 8

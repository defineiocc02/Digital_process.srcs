"""Regression tests for the independent physical-CDAC revalidation runner."""

from dataclasses import replace

import numpy as np

from analysis.physical_cdac_mismatch_20260729.physical_cdac import (
    PhysicalCdacConfig,
    draw_physical_chip,
    nominal_weights_q8,
)
from analysis.physical_cdac_mismatch_20260729.run_revalidation import (
    DECODERS,
    decoder_weight_set,
    evaluate_main_chip,
    headroom_guarded_weights,
    ideal_acceptance,
    noiseless_config,
    sum_normalized_weights,
)


def test_sum_normalization_uses_nominal_total() -> None:
    nominal = np.array([256.0, 512.0, 1024.0])
    calibrated = nominal * 1.007
    normalized, scale = sum_normalized_weights(calibrated, nominal)
    assert np.isclose(np.sum(normalized), np.sum(nominal), rtol=0.0, atol=1e-10)
    assert np.isclose(scale, 1.0 / 1.007, rtol=0.0, atol=1e-12)


def test_headroom_guard_never_increases_calibrated_gain() -> None:
    nominal = np.array([256.0, 512.0, 1024.0])
    high, high_scale = headroom_guarded_weights(nominal * 1.007, nominal)
    low, low_scale = headroom_guarded_weights(nominal * 0.993, nominal)
    assert high_scale < 1.0
    assert np.isclose(np.sum(high), np.sum(nominal), rtol=0.0, atol=1e-10)
    assert low_scale == 1.0
    assert np.array_equal(low, nominal * 0.993)


def test_decoder_normalization_does_not_require_oracle_sum() -> None:
    cfg = noiseless_config(n_chips=1, n_fft=4096)
    physical_cfg = PhysicalCdacConfig()
    chip = draw_physical_chip(physical_cfg, chip_id=128)
    nominal = nominal_weights_q8(physical_cfg)
    weights, scales = decoder_weight_set(chip.weights_q8, nominal, cfg, chip_id=128)
    assert 0.98 < scales["CAL_SUM_NORM_SRM"] < 1.02
    assert np.isclose(
        np.sum(weights["CAL_SUM_NORM_SRM"]),
        np.sum(nominal),
        rtol=0.0,
        atol=1e-8,
    )


def test_ideal_arithmetic_and_stochastic_srm_are_separate() -> None:
    result = ideal_acceptance()
    assert result["passed"] is True
    assert 98.0 < result["direct_quantizer_full_scale"]["sndr_db"] < 98.2
    assert 97.9 < result["segmented_cdac_expected_srm"]["sndr_db"] < 98.2
    assert 97.9 < result["segmented_cdac_exact_physical_residue"]["sndr_db"] < 98.2
    assert 97.0 < result["rtl_22_stochastic_srm_sndr_db"]["median"] < 97.3


def test_known_fullscale_gain_tail_is_reduced_by_sum_normalization() -> None:
    cfg = noiseless_config(n_chips=1, n_fft=4096)
    rows, _ = evaluate_main_chip(128, cfg, PhysicalCdacConfig())
    by_decoder = {str(row["decoder"]): row for row in rows}
    assert set(by_decoder) == set(DECODERS)
    current = by_decoder["CAL_CURRENT_SRM"]
    normalized = by_decoder["CAL_SUM_NORM_SRM"]
    guarded = by_decoder["CAL_HEADROOM_GUARD_SRM"]
    assert float(current["fullscale_saturation_fraction"]) > 0.05
    assert float(normalized["fullscale_saturation_fraction"]) < 0.005
    assert float(normalized["fullscale_sndr_db"]) > float(current["fullscale_sndr_db"]) + 20.0
    assert float(guarded["fullscale_sndr_db"]) > float(current["fullscale_sndr_db"]) + 20.0


def test_zero_physical_sigma_is_seed_independent() -> None:
    physical_cfg = replace(
        PhysicalCdacConfig(),
        unit_cap_sigma_pct=0.0,
        node_parasitic_sigma_pct=0.0,
        comparator_input_sigma_pct=0.0,
    )
    first = draw_physical_chip(physical_cfg, chip_id=1)
    second = draw_physical_chip(physical_cfg, chip_id=999)
    assert np.array_equal(first.weights_q8, second.weights_q8)

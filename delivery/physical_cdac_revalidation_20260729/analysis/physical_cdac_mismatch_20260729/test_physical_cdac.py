"""Tests for the physical segmented-CDAC mismatch model."""

from dataclasses import replace

import numpy as np

from analysis.physical_cdac_mismatch_20260729.physical_cdac import (
    PhysicalCdacConfig,
    draw_physical_chip,
    nominal_weights_q8,
    nominal_weights_v,
)
from analysis.physical_cdac_mismatch_20260729.run_physical_mismatch import (
    ideal_16bit_acceptance_gate,
)


def test_nominal_solver_reproduces_project_weight_table() -> None:
    cfg = PhysicalCdacConfig()
    relative = nominal_weights_v(cfg) / nominal_weights_v(cfg)[0]
    expected = np.array(
        [
            1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 33.525, 67.05, 134.10,
            268.20, 316.9065625, 316.9065625, 633.813125, 1267.62625,
            2535.2525, 5031.086776041666, 5031.086776041666,
            10062.173552083332, 20124.347104166663, 40248.694208333327,
        ]
    )
    assert np.allclose(relative, expected, rtol=0.0, atol=1e-9)


def test_zero_sigma_returns_nominal_physical_weights() -> None:
    cfg = replace(
        PhysicalCdacConfig(),
        unit_cap_sigma_pct=0.0,
        node_parasitic_sigma_pct=0.0,
        comparator_input_sigma_pct=0.0,
    )
    chip = draw_physical_chip(cfg, 7)
    assert np.allclose(chip.weights_q8, nominal_weights_q8(cfg), rtol=0.0, atol=1e-10)
    assert np.all(chip.cap_rel_error == 0.0)
    assert np.all(chip.bridge_rel_error == 0.0)


def test_seeded_physical_draw_is_deterministic() -> None:
    cfg = PhysicalCdacConfig()
    first = draw_physical_chip(cfg, 19)
    second = draw_physical_chip(cfg, 19)
    assert np.array_equal(first.bit_caps_ff, second.bit_caps_ff)
    assert np.array_equal(first.bridge_caps_ff, second.bridge_caps_ff)
    assert np.array_equal(first.weights_q8, second.weights_q8)


def test_larger_cap_has_smaller_relative_sigma_empirically() -> None:
    cfg = replace(
        PhysicalCdacConfig(),
        node_parasitic_sigma_pct=0.0,
        comparator_input_sigma_pct=0.0,
    )
    errors = np.array([draw_physical_chip(cfg, chip_id).cap_rel_error for chip_id in range(4096)])
    sigma_1cu = float(np.std(errors[:, 0], ddof=1))
    sigma_64cu = float(np.std(errors[:, -1], ddof=1))
    assert 7.2 < sigma_1cu / sigma_64cu < 8.8


def test_noiseless_nominal_path_reaches_ideal_16bit_sndr() -> None:
    gate = ideal_16bit_acceptance_gate()
    assert gate["passed"] is True
    assert 98.0 < gate["direct_quantizer_sndr_db"] < 98.2
    assert 97.9 < gate["segmented_cdac_deterministic_srm_sndr_db"] < 98.2
    assert 97.0 < gate["rtl_22_decision_stochastic_srm_sndr_db"] < 97.3
    assert gate["segmented_cdac_no_srm_sndr_db"] < 95.3

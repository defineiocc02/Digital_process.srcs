"""Focused regression tests for the complete behavioral model."""

from __future__ import annotations

from dataclasses import replace

import numpy as np

from .full_sar_model import (
    FullSarConfig,
    SRM_LUT_Q8,
    evaluate_chip,
    full_scale_ramp,
    ideal_weight_q8,
    manufacture_chip_q8,
    rtl_reconstruct,
    run_normal_sar_conversion,
    run_rtl_equivalent_calibration,
)


def test_srm_lut_matches_rtl_endpoints_and_midpoint() -> None:
    assert len(SRM_LUT_Q8) == 23
    assert int(SRM_LUT_Q8[0]) == -258
    assert int(SRM_LUT_Q8[11]) == 0
    assert int(SRM_LUT_Q8[22]) == 258
    assert np.array_equal(SRM_LUT_Q8, -SRM_LUT_Q8[::-1])


def test_calibration_populates_all_weights() -> None:
    cfg = FullSarConfig(n_chips=1)
    physical = manufacture_chip_q8(cfg, chip_id=0)
    calibrated, trace = run_rtl_equivalent_calibration(physical, cfg, chip_id=0)
    assert len(trace) == 14
    assert np.all(calibrated > 0)
    assert np.array_equal(calibrated[:6], ideal_weight_q8(cfg)[:6])


def test_full_conversion_shapes_and_srm_range() -> None:
    cfg = replace(
        FullSarConfig(n_chips=1),
        sampling_noise_lsb=0.0,
        normal_comparator_noise_lsb=0.0,
    )
    physical = ideal_weight_q8(cfg).astype(float)
    stimulus = np.array([-20000.0, -1.0, 0.0, 1.0, 20000.0])
    conversion = run_normal_sar_conversion(
        stimulus, physical, cfg, chip_id=0, stream_id=99
    )
    assert conversion.raw_bits.shape == (len(stimulus), cfg.cap_num)
    assert conversion.srm_ones_count.shape == stimulus.shape
    assert np.all((conversion.srm_ones_count >= 0) & (conversion.srm_ones_count <= 22))
    decoded, saturation = rtl_reconstruct(
        conversion.raw_bits,
        ideal_weight_q8(cfg),
        cfg,
        conversion.srm_residue_q8,
    )
    assert decoded.shape == stimulus.shape
    assert saturation == 0.0
    assert np.all(np.diff(decoded) >= 0)


def test_quick_end_to_end_metrics_exist() -> None:
    cfg = replace(
        FullSarConfig(n_chips=1),
        n_fft=1024,
        static_samples_per_code=1,
    )
    metrics, trace = evaluate_chip(
        chip_id=0,
        cfg=cfg,
        static_samples_per_code=1,
        retain_linearity_arrays=False,
    )
    assert len(metrics) == 4
    assert {item.decoder for item in metrics} == {
        "NOMINAL_NO_SRM",
        "CAL_NO_SRM",
        "CAL_SRM",
        "ORACLE_SRM",
    }
    assert trace["srm"]["decision_count"] == 22
    assert all(np.isfinite(item.dynamic_sndr_db) for item in metrics)
    assert all(np.isfinite(item.inl_pp_lsb) for item in metrics)


def test_full_range_ramp_has_requested_density() -> None:
    cfg = FullSarConfig()
    ramp = full_scale_ramp(cfg, samples_per_code=2)
    assert len(ramp) == 2 * (1 << cfg.output_bits)
    assert np.all(np.diff(ramp) > 0)

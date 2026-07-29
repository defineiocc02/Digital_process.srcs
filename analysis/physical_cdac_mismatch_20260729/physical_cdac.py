"""Physical segmented-CDAC mismatch and effective-weight solver.

The topology and center assumptions are ported from the archived project
MATLAB model ``cap_array_calib_16b.m``.  Random mismatch is applied to physical
capacitors before the four-node capacitance matrix is solved.  This avoids the
withdrawn shortcut of assigning one arbitrary relative sigma to each final
reconstruction weight.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Tuple

import numpy as np


@dataclass(frozen=True)
class PhysicalCdacConfig:
    """Traceable physical assumptions for the 6+4+5+5 split CDAC."""

    target_bits: int = 16
    frac_bits: int = 8
    vref_v: float = 3.3
    c_unit_ff: float = 8.0
    node_parasitic_ratio: float = 0.05
    comparator_input_ff: float = 5.0
    segment_ratios: Tuple[Tuple[float, ...], ...] = (
        (1, 2, 4, 8, 16, 32),
        (2, 4, 8, 16),
        (2, 2, 4, 8, 16),
        (8, 8, 16, 32, 64),
    )
    bridge_units: Tuple[float, ...] = (4, 4, 12)

    # Project-MATLAB center point, not a foundry sign-off value.
    unit_cap_sigma_pct: float = 1.2
    node_parasitic_sigma_pct: float = 2.0
    comparator_input_sigma_pct: float = 2.0
    seed: int = 20260729

    def validate(self) -> None:
        if self.target_bits != 16 or self.frac_bits != 8:
            raise ValueError("The active project contract requires signed-16/Q8.")
        if len(self.segment_ratios) < 2:
            raise ValueError("A split CDAC requires at least two segments.")
        if len(self.bridge_units) != len(self.segment_ratios) - 1:
            raise ValueError("One bridge capacitor is required between adjacent segments.")
        if sum(len(segment) for segment in self.segment_ratios) != 20:
            raise ValueError("The local calibration and reconstruction contract requires 20 weights.")
        positive = (
            self.vref_v,
            self.c_unit_ff,
            self.comparator_input_ff,
            *self.bridge_units,
            *(value for segment in self.segment_ratios for value in segment),
        )
        if any(value <= 0.0 for value in positive):
            raise ValueError("Physical capacitor and voltage values must be positive.")
        if self.node_parasitic_ratio < 0.0:
            raise ValueError("node_parasitic_ratio must be non-negative.")
        if min(
            self.unit_cap_sigma_pct,
            self.node_parasitic_sigma_pct,
            self.comparator_input_sigma_pct,
        ) < 0.0:
            raise ValueError("Mismatch sigma values must be non-negative.")


@dataclass(frozen=True)
class PhysicalChip:
    """One deterministic physical capacitor realization and solved weights."""

    chip_id: int
    bit_caps_ff: np.ndarray
    bridge_caps_ff: np.ndarray
    node_parasitic_ff: float
    comparator_input_ff: float
    weights_v: np.ndarray
    weights_q8: np.ndarray
    effective_weight_rel_error: np.ndarray
    cap_rel_error: np.ndarray
    bridge_rel_error: np.ndarray


def stable_rng(cfg: PhysicalCdacConfig, *items: int) -> np.random.Generator:
    return np.random.default_rng(np.random.SeedSequence([cfg.seed, *map(int, items)]))


def topology_arrays(cfg: PhysicalCdacConfig) -> tuple[np.ndarray, tuple[np.ndarray, ...]]:
    """Return flattened bit-cap unit counts and per-segment indices."""

    cfg.validate()
    ratios = np.concatenate([np.asarray(segment, dtype=float) for segment in cfg.segment_ratios])
    indices = []
    start = 0
    for segment in cfg.segment_ratios:
        stop = start + len(segment)
        indices.append(np.arange(start, stop, dtype=int))
        start = stop
    return ratios, tuple(indices)


def nominal_components(
    cfg: PhysicalCdacConfig,
) -> tuple[np.ndarray, np.ndarray, float, float, tuple[np.ndarray, ...]]:
    """Return nominal bit, bridge, node-parasitic, and comparator capacitances."""

    ratios, indices = topology_arrays(cfg)
    return (
        ratios * cfg.c_unit_ff,
        np.asarray(cfg.bridge_units, dtype=float) * cfg.c_unit_ff,
        cfg.node_parasitic_ratio * cfg.c_unit_ff,
        cfg.comparator_input_ff,
        indices,
    )


def solve_effective_weights(
    bit_caps_ff: np.ndarray,
    segment_indices: tuple[np.ndarray, ...],
    bridge_caps_ff: np.ndarray,
    node_parasitic_ff: float,
    comparator_input_ff: float,
    vref_v: float,
) -> tuple[np.ndarray, float]:
    """Solve the segmented capacitor network and return bit weights in volts."""

    bit_caps = np.asarray(bit_caps_ff, dtype=float)
    bridges = np.asarray(bridge_caps_ff, dtype=float)
    n_segments = len(segment_indices)
    if len(bridges) != n_segments - 1:
        raise ValueError("bridge count does not match segment count")
    if np.any(bit_caps <= 0.0) or np.any(bridges <= 0.0):
        raise ValueError("physical capacitors must remain positive")

    capacitance_matrix = np.zeros((n_segments, n_segments), dtype=float)
    for segment in range(n_segments):
        self_cap = float(np.sum(bit_caps[segment_indices[segment]])) + node_parasitic_ff
        if segment == n_segments - 1:
            self_cap += comparator_input_ff
        if segment > 0:
            self_cap += bridges[segment - 1]
        if segment < n_segments - 1:
            self_cap += bridges[segment]
        capacitance_matrix[segment, segment] = self_cap
    for segment, bridge in enumerate(bridges):
        capacitance_matrix[segment, segment + 1] = -bridge
        capacitance_matrix[segment + 1, segment] = -bridge

    charge = np.zeros((n_segments, len(bit_caps)), dtype=float)
    for segment, indices in enumerate(segment_indices):
        charge[segment, indices] = bit_caps[indices] * vref_v
    node_voltage = np.linalg.solve(capacitance_matrix, charge)
    weights_v = node_voltage[-1]
    full_scale_v = float(np.linalg.solve(capacitance_matrix, np.sum(charge, axis=1))[-1])
    return weights_v, full_scale_v


def nominal_weights_v(cfg: PhysicalCdacConfig) -> np.ndarray:
    bit_caps, bridges, parasitic, comparator, indices = nominal_components(cfg)
    weights, _ = solve_effective_weights(
        bit_caps,
        indices,
        bridges,
        parasitic,
        comparator,
        cfg.vref_v,
    )
    return weights


def weights_v_to_q8(weights_v: np.ndarray, cfg: PhysicalCdacConfig) -> np.ndarray:
    """Map physical voltage weights to the fixed nominal-physical-LSB Q8 domain."""

    nominal_lsb_v = float(nominal_weights_v(cfg)[0])
    return np.asarray(weights_v, dtype=float) / nominal_lsb_v * float(1 << cfg.frac_bits)


def nominal_weights_q8(cfg: PhysicalCdacConfig) -> np.ndarray:
    return weights_v_to_q8(nominal_weights_v(cfg), cfg)


def draw_physical_chip(cfg: PhysicalCdacConfig, chip_id: int) -> PhysicalChip:
    """Draw physical capacitor mismatch, then solve effective decision weights.

    Bit and bridge capacitor relative sigma obeys ``sigma_unit/sqrt(Nunit)``.
    Node parasitic and comparator input capacitance retain the project MATLAB's
    independent scalar 2% assumptions.  No effective weight is directly
    perturbed.
    """

    bit_nom, bridge_nom, parasitic_nom, comparator_nom, indices = nominal_components(cfg)
    ratios, _ = topology_arrays(cfg)
    bridge_units = np.asarray(cfg.bridge_units, dtype=float)
    rng = stable_rng(cfg, 1101, chip_id)
    sigma_unit = cfg.unit_cap_sigma_pct / 100.0

    bit_rel_error = sigma_unit / np.sqrt(ratios) * rng.standard_normal(len(ratios))
    bridge_rel_error = sigma_unit / np.sqrt(bridge_units) * rng.standard_normal(len(bridge_units))
    bit_caps = bit_nom * np.maximum(1.0 + bit_rel_error, 1e-6)
    bridge_caps = bridge_nom * np.maximum(1.0 + bridge_rel_error, 1e-6)
    parasitic = parasitic_nom * max(
        1.0 + cfg.node_parasitic_sigma_pct / 100.0 * float(rng.standard_normal()),
        1e-6,
    )
    comparator = comparator_nom * max(
        1.0 + cfg.comparator_input_sigma_pct / 100.0 * float(rng.standard_normal()),
        1e-6,
    )
    weights_v, _ = solve_effective_weights(
        bit_caps,
        indices,
        bridge_caps,
        parasitic,
        comparator,
        cfg.vref_v,
    )
    nominal = nominal_weights_v(cfg)
    return PhysicalChip(
        chip_id=chip_id,
        bit_caps_ff=bit_caps,
        bridge_caps_ff=bridge_caps,
        node_parasitic_ff=parasitic,
        comparator_input_ff=comparator,
        weights_v=weights_v,
        weights_q8=weights_v_to_q8(weights_v, cfg),
        effective_weight_rel_error=weights_v / nominal - 1.0,
        cap_rel_error=bit_rel_error,
        bridge_rel_error=bridge_rel_error,
    )


def redundancy_margins_lsb(weights_q8: np.ndarray, frac_bits: int = 8) -> np.ndarray:
    """Return sorted low-weight coverage margin in nominal physical-LSB units."""

    weights_lsb = np.sort(np.asarray(weights_q8, dtype=float) / float(1 << frac_bits))
    margins = np.zeros_like(weights_lsb)
    lower_sum = 0.0
    lsb = float(weights_lsb[0])
    for index, weight in enumerate(weights_lsb):
        margins[index] = lower_sum + lsb - weight
        lower_sum += float(weight)
    return margins

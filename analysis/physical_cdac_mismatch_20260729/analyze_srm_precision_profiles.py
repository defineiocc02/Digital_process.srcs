"""Evaluate finite-sample SRM profiles against the ideal 16-bit limit.

The paper-faithful profile keeps 22 stochastic decisions and the current RTL
inverse-normal LUT. Candidate posterior-mean LUTs are trained on a uniform
full-scale ramp and evaluated on an independent coherent sine capture. The
candidate profiles are analysis results only; this script does not modify RTL.
"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path
from typing import Dict, Tuple

import matplotlib.pyplot as plt
import numpy as np
from scipy.special import ndtr
from scipy.stats import binom

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from analysis.full_sar_behavioral_20260729.full_sar_model import (
    SRM_LUT_Q8,
    coherent_sine,
    full_scale_ramp,
    rtl_reconstruct,
    run_normal_sar_conversion,
    spectrum_metrics,
    stable_rng,
)
from analysis.physical_cdac_mismatch_20260729.physical_cdac import (
    PhysicalCdacConfig,
    nominal_weights_q8,
)
from analysis.physical_cdac_mismatch_20260729.run_physical_mismatch import (
    noiseless_sar_config,
)

ROOT = Path(__file__).resolve().parent
OUTDIR = ROOT / "outputs"


def posterior_mean_lut(
    residue_q8: np.ndarray,
    decision_count: int,
    comparator_sigma_lsb: float,
) -> np.ndarray:
    """Return a symmetric posterior-mean LUT for a uniform-input prior."""

    probability = ndtr(residue_q8 / (comparator_sigma_lsb * 256.0))
    counts = np.arange(decision_count + 1)
    likelihood = binom.pmf(counts[None, :], decision_count, probability[:, None])
    estimate = (likelihood.T @ residue_q8) / np.maximum(likelihood.sum(axis=0), 1e-300)
    estimate = 0.5 * (estimate - estimate[::-1])
    return np.rint(estimate).astype(np.int64)


def evaluate_profile(
    decision_count: int,
    comparator_sigma_lsb: float,
    lut_q8: np.ndarray,
    trials: int = 16,
) -> Tuple[float, float, float, float]:
    """Evaluate one SRM profile on an independent full-scale sine."""

    cfg = noiseless_sar_config(n_chips=1, n_fft=131072)
    sine, _, _ = coherent_sine(cfg, chip_id=91)
    weights_q8 = nominal_weights_q8(
        PhysicalCdacConfig(
            unit_cap_sigma_pct=0.0,
            node_parasitic_sigma_pct=0.0,
            comparator_input_sigma_pct=0.0,
        )
    )
    conversion = run_normal_sar_conversion(
        sine,
        weights_q8,
        cfg,
        chip_id=91,
        stream_id=9101,
        include_random_noise=False,
        stochastic_srm=False,
    )
    probability = ndtr(
        conversion.physical_residue_q8 / (comparator_sigma_lsb * 256.0)
    )
    sndr_values = []
    for trial in range(trials):
        rng = stable_rng(cfg, 9201, decision_count, int(comparator_sigma_lsb * 1000), trial)
        count = rng.binomial(decision_count, probability)
        codes, _ = rtl_reconstruct(
            conversion.raw_bits,
            weights_q8,
            cfg,
            residue_q8=lut_q8[count],
        )
        sndr_values.append(spectrum_metrics(codes, cfg)["sndr_db"])
    values = np.asarray(sndr_values)
    return float(np.mean(values)), float(np.std(values, ddof=1)), float(np.min(values)), float(np.max(values))


def main() -> None:
    OUTDIR.mkdir(exist_ok=True)
    cfg = noiseless_sar_config(n_chips=1, n_fft=65536)
    weights_q8 = nominal_weights_q8(
        PhysicalCdacConfig(
            unit_cap_sigma_pct=0.0,
            node_parasitic_sigma_pct=0.0,
            comparator_input_sigma_pct=0.0,
        )
    )
    ramp = full_scale_ramp(cfg, samples_per_code=1)
    training = run_normal_sar_conversion(
        ramp,
        weights_q8,
        cfg,
        chip_id=90,
        stream_id=9100,
        include_random_noise=False,
        stochastic_srm=False,
    )

    profiles: Dict[str, Tuple[int, float, np.ndarray, str]] = {
        "RTL_CURRENT_22": (22, 0.5, SRM_LUT_Q8, "Current paper-faithful RTL profile"),
        "POSTERIOR_RAMP_22": (
            22,
            0.5,
            posterior_mean_lut(training.physical_residue_q8, 22, 0.5),
            "Analysis-only posterior LUT; same 22 decisions",
        ),
        "POSTERIOR_RAMP_128": (
            128,
            0.5,
            posterior_mean_lut(training.physical_residue_q8, 128, 0.5),
            "Analysis-only precision profile; changes latency and counter/LUT size",
        ),
    }

    rows = []
    lut_rows = []
    for name, (decisions, sigma_lsb, lut, note) in profiles.items():
        mean, std, minimum, maximum = evaluate_profile(decisions, sigma_lsb, lut)
        rows.append(
            {
                "profile": name,
                "decision_count": decisions,
                "comparator_sigma_lsb": sigma_lsb,
                "sndr_mean_db": mean,
                "sndr_std_db": std,
                "sndr_min_db": minimum,
                "sndr_max_db": maximum,
                "note": note,
            }
        )
        for count, value in enumerate(lut):
            lut_rows.append({"profile": name, "count": count, "residue_q8": int(value)})

    for path, data in (
        (OUTDIR / "srm_precision_profiles.csv", rows),
        (OUTDIR / "srm_lut_candidates.csv", lut_rows),
    ):
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(data[0]))
            writer.writeheader()
            writer.writerows(data)

    payload = {
        "status": "complete",
        "evidence_boundary": (
            "Candidate LUTs are trained on a nominal uniform-ramp residue prior and are not RTL-qualified. "
            "Only RTL_CURRENT_22 reproduces the current project implementation."
        ),
        "profiles": rows,
    }
    (OUTDIR / "srm_precision_profiles.json").write_text(
        json.dumps(payload, indent=2), encoding="utf-8"
    )

    fig, axis = plt.subplots(figsize=(7.4, 4.2))
    names = [row["profile"] for row in rows]
    means = np.array([row["sndr_mean_db"] for row in rows], dtype=float)
    errors = np.array([row["sndr_std_db"] for row in rows], dtype=float)
    bars = axis.bar(names, means, yerr=errors, capsize=4, color=["#147d92", "#299c59", "#6d5aa8"])
    axis.axhline(98.079, color="#b34a3c", linestyle="--", label="Ideal 16-bit quantizer")
    axis.set_ylim(96.8, 98.2)
    axis.set_ylabel("Noiseless full-scale SNDR (dB)")
    axis.set_title("Finite-sample SRM precision profiles")
    axis.tick_params(axis="x", rotation=15)
    axis.grid(axis="y", alpha=0.25)
    axis.legend()
    axis.bar_label(bars, labels=[f"{value:.3f}" for value in means], padding=3)
    fig.tight_layout()
    fig.savefig(OUTDIR / "fig_srm_precision_profiles.png", dpi=180)
    fig.savefig(OUTDIR / "fig_srm_precision_profiles.pdf")
    plt.close(fig)

    for row in rows:
        print(
            f"{row['profile']:22s} decisions={row['decision_count']:3d} "
            f"SNDR={row['sndr_mean_db']:.3f}+/-{row['sndr_std_db']:.3f} dB"
        )


if __name__ == "__main__":
    main()

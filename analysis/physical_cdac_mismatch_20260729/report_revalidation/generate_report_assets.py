"""Generate deterministic LaTeX tables for the physical-CDAC revalidation report."""

from __future__ import annotations

import csv
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OUT = ROOT / "outputs_revalidation"

DECODER_LABELS = {
    "NOMINAL_SRM": "标称权重+SRM",
    "CAL_CURRENT_SRM": "当前校准+SRM",
    "CAL_SUM_NORM_SRM": "对称总和归一化",
    "CAL_HEADROOM_GUARD_SRM": "单边余量保护",
    "CAL_ZERO_COMP_ERROR_SRM": "零校准比较误差",
    "ORACLE_SRM": "物理权重上限",
}


def fmt(value: float, digits: int = 3) -> str:
    return f"{float(value):.{digits}f}"


def tex_macro(name: str, value: object) -> str:
    return rf"\newcommand{{\{name}}}{{{value}}}"


def read_csv(name: str) -> list[dict[str, str]]:
    with (OUT / name).open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def main() -> None:
    summary = json.loads((OUT / "summary.json").read_text(encoding="utf-8"))
    main_rows = read_csv("per_chip_main_metrics.csv")

    ideal = summary["ideal_acceptance"]
    macros = [
        tex_macro("ExperimentVersion", summary["experiment_version"]),
        tex_macro("ChipCount", summary["main_completed_chips"]),
        tex_macro("FftLength", summary["config"]["n_fft"]),
        tex_macro("IdealDirectSndr", fmt(ideal["direct_quantizer_full_scale"]["sndr_db"])),
        tex_macro("IdealNoSrmSndr", fmt(ideal["segmented_cdac_no_srm"]["sndr_db"])),
        tex_macro("IdealExactResidueSndr", fmt(ideal["segmented_cdac_exact_physical_residue"]["sndr_db"])),
        tex_macro("IdealExpectedSrmSndr", fmt(ideal["segmented_cdac_expected_srm"]["sndr_db"])),
        tex_macro("IdealStochasticSrmSndr", fmt(ideal["rtl_22_stochastic_srm_sndr_db"]["median"])),
        tex_macro("CurrentFullMedian", fmt(summary["main_summary"]["CAL_CURRENT_SRM"]["fullscale_sndr_db"]["median"])),
        tex_macro("CurrentFullMinimum", fmt(summary["main_summary"]["CAL_CURRENT_SRM"]["fullscale_sndr_db"]["min"])),
        tex_macro("CurrentBackoffMedian", fmt(summary["main_summary"]["CAL_CURRENT_SRM"]["backoff_sndr_db"]["median"])),
        tex_macro("GuardFullMinimum", fmt(summary["main_summary"]["CAL_HEADROOM_GUARD_SRM"]["fullscale_sndr_db"]["min"])),
        tex_macro("GuardFullMedian", fmt(summary["main_summary"]["CAL_HEADROOM_GUARD_SRM"]["fullscale_sndr_db"]["median"])),
        tex_macro("CurrentInlMedian", fmt(summary["main_summary"]["CAL_CURRENT_SRM"]["inl_max_lsb"]["median"])),
        tex_macro("CurrentDnlMedian", fmt(summary["main_summary"]["CAL_CURRENT_SRM"]["dnl_max_lsb"]["median"])),
        tex_macro("CurrentMissingMedian", int(summary["main_summary"]["CAL_CURRENT_SRM"]["missing_codes"]["median"])),
        tex_macro("CurrentMissingMaximum", int(summary["main_summary"]["CAL_CURRENT_SRM"]["missing_codes"]["max"])),
        tex_macro("NominalMissingMedian", int(summary["main_summary"]["NOMINAL_SRM"]["missing_codes"]["median"])),
        tex_macro("CurrentWeightRmseMedian", fmt(summary["main_summary"]["CAL_CURRENT_SRM"]["weight_rmse_gain_aligned_lsb"]["median"])),
        tex_macro("NominalWeightRmseMedian", fmt(summary["main_summary"]["NOMINAL_SRM"]["weight_rmse_gain_aligned_lsb"]["median"])),
    ]
    (HERE / "generated_metrics.tex").write_text("\n".join(macros) + "\n", encoding="utf-8")

    dynamic_lines = []
    static_lines = []
    for decoder, label in DECODER_LABELS.items():
        m = summary["main_summary"][decoder]
        dynamic_lines.append(
            " & ".join(
                [
                    label,
                    fmt(m["fullscale_sndr_db"]["median"]),
                    fmt(m["fullscale_sndr_db"]["p05"]),
                    fmt(m["fullscale_sndr_db"]["min"]),
                    fmt(m["backoff_sndr_db"]["median"]),
                    fmt(m["fullscale_sfdr_db"]["median"]),
                    fmt(100.0 * m["fullscale_saturation_fraction"]["max"], 2),
                ]
            )
            + r" \\"
        )
        static_lines.append(
            " & ".join(
                [
                    label,
                    fmt(m["dnl_min_lsb"]["median"]),
                    fmt(m["dnl_max_lsb"]["median"]),
                    fmt(m["inl_min_lsb"]["median"]),
                    fmt(m["inl_max_lsb"]["median"]),
                    str(int(m["missing_codes"]["median"])),
                    str(int(m["missing_codes"]["max"])),
                ]
            )
            + r" \\"
        )
    (HERE / "dynamic_table_rows.tex").write_text("\n".join(dynamic_lines) + "\n\\bottomrule\n", encoding="utf-8")
    (HERE / "static_table_rows.tex").write_text("\n".join(static_lines) + "\n\\bottomrule\n", encoding="utf-8")

    pass_lines = []
    for decoder in ("CAL_CURRENT_SRM", "CAL_SUM_NORM_SRM", "CAL_HEADROOM_GUARD_SRM"):
        p = summary["pass_rates"][decoder]
        pass_lines.append(
            " & ".join(
                [
                    DECODER_LABELS[decoder],
                    f"{p['fullscale']['ge_90_db']}/512",
                    f"{p['fullscale']['ge_94_db']}/512",
                    f"{p['fullscale']['ge_95_db']}/512",
                    f"{p['backoff']['ge_94_db']}/512",
                ]
            )
            + r" \\"
        )
    (HERE / "pass_table_rows.tex").write_text("\n".join(pass_lines) + "\n\\bottomrule\n", encoding="utf-8")

    current = {
        int(row["chip_id"]): row for row in main_rows if row["decoder"] == "CAL_CURRENT_SRM"
    }
    symmetric = {
        int(row["chip_id"]): row for row in main_rows if row["decoder"] == "CAL_SUM_NORM_SRM"
    }
    guard = {
        int(row["chip_id"]): row for row in main_rows if row["decoder"] == "CAL_HEADROOM_GUARD_SRM"
    }
    tail_lines = []
    for chip_id, row in sorted(current.items(), key=lambda item: float(item[1]["fullscale_sndr_db"]))[:10]:
        tail_lines.append(
            " & ".join(
                [
                    str(chip_id),
                    fmt(row["fullscale_sndr_db"]),
                    fmt(100.0 * float(row["fullscale_saturation_fraction"]), 2),
                    fmt(symmetric[chip_id]["fullscale_sndr_db"]),
                    fmt(guard[chip_id]["fullscale_sndr_db"]),
                    fmt(100.0 * float(guard[chip_id]["fullscale_saturation_fraction"]), 2),
                    fmt(guard[chip_id]["sum_normalization_scale"], 6),
                ]
            )
            + r" \\"
        )
    (HERE / "tail_table_rows.tex").write_text("\n".join(tail_lines) + "\n\\bottomrule\n", encoding="utf-8")

    sigma_rows = read_csv("sigma_summary.csv")
    sigma_lines = []
    for sigma in summary["sigma_values_pct"]:
        selected = {
            row["decoder"]: row
            for row in sigma_rows
            if float(row["unit_cap_sigma_pct"]) == float(sigma)
            and row["metric"] == "sndr_db"
        }
        sigma_lines.append(
            " & ".join(
                [
                    fmt(sigma, 1),
                    fmt(selected["NOMINAL_SRM"]["median"]),
                    fmt(selected["CAL_CURRENT_SRM"]["median"]),
                    fmt(selected["CAL_HEADROOM_GUARD_SRM"]["median"]),
                    fmt(selected["ORACLE_SRM"]["median"]),
                ]
            )
            + r" \\"
        )
    (HERE / "sigma_table_rows.tex").write_text("\n".join(sigma_lines) + "\n\\bottomrule\n", encoding="utf-8")

    amplitude_rows = read_csv("amplitude_summary.csv")
    amplitude_lines = []
    for amplitude in summary["amplitude_ratios"]:
        selected = {
            row["decoder"]: row
            for row in amplitude_rows
            if float(row["amplitude_ratio"]) == float(amplitude)
            and row["metric"] == "sndr_db"
        }
        amplitude_lines.append(
            " & ".join(
                [
                    fmt(amplitude, 5),
                    fmt(selected["NOMINAL_SRM"]["median"]),
                    fmt(selected["CAL_CURRENT_SRM"]["median"]),
                    fmt(selected["CAL_HEADROOM_GUARD_SRM"]["median"]),
                    fmt(selected["ORACLE_SRM"]["median"]),
                ]
            )
            + r" \\"
        )
    (HERE / "amplitude_table_rows.tex").write_text("\n".join(amplitude_lines) + "\n\\bottomrule\n", encoding="utf-8")


if __name__ == "__main__":
    main()

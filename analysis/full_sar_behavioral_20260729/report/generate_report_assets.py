"""Generate LaTeX metrics and tables from the authoritative campaign JSON."""

from __future__ import annotations

import json
from pathlib import Path


REPORT_DIR = Path(__file__).resolve().parent
ROOT = REPORT_DIR.parent
SUMMARY_PATH = ROOT / "outputs" / "summary.json"


def metric(payload: dict, decoder: str, name: str, statistic: str) -> float:
    return float(payload["summary"][decoder][name][statistic])


def command(name: str, value: str) -> str:
    return rf"\newcommand{{\{name}}}{{{value}}}"


def generate_metrics(payload: dict) -> str:
    cfg = payload["config"]
    srm_sndr_gain = (
        metric(payload, "CAL_SRM", "dynamic_sndr_db", "median")
        - metric(payload, "CAL_NO_SRM", "dynamic_sndr_db", "median")
    )
    srm_inl_reduction = (
        metric(payload, "CAL_NO_SRM", "inl_pp_lsb", "median")
        - metric(payload, "CAL_SRM", "inl_pp_lsb", "median")
    )
    lines = [
        "% Generated from outputs/summary.json. Do not edit manually.",
        command("ChipCount", str(payload["completed_chips"])),
        command("DecoderRows", str(payload["decoder_rows"])),
        command("FftLength", str(cfg["n_fft"])),
        command("SampleRateMHz", f"{cfg['fs_hz'] / 1e6:.3f}"),
        command(
            "RuntimeSeconds",
            f"{payload['checkpoint_span_seconds']:.2f}",
        ),
        command(
            "CalSndrMedian",
            f"{metric(payload, 'CAL_SRM', 'dynamic_sndr_db', 'median'):.3f}",
        ),
        command(
            "CalSndrPZeroOne",
            f"{metric(payload, 'CAL_SRM', 'dynamic_sndr_db', 'p01'):.3f}",
        ),
        command(
            "CalSfdrMedian",
            f"{metric(payload, 'CAL_SRM', 'dynamic_sfdr_db', 'median'):.3f}",
        ),
        command(
            "CalInlMedian",
            f"{metric(payload, 'CAL_SRM', 'inl_pp_lsb', 'median'):.3f}",
        ),
        command(
            "CalInlPNinetyFive",
            f"{metric(payload, 'CAL_SRM', 'inl_pp_lsb', 'p95'):.3f}",
        ),
        command(
            "CalDnlMedian",
            f"{metric(payload, 'CAL_SRM', 'dnl_pp_lsb', 'median'):.3f}",
        ),
        command(
            "CalDnlPNinetyFive",
            f"{metric(payload, 'CAL_SRM', 'dnl_pp_lsb', 'p95'):.3f}",
        ),
        command(
            "CalMissingMedian",
            f"{metric(payload, 'CAL_SRM', 'missing_codes', 'median'):.0f}",
        ),
        command(
            "CalMissingMax",
            f"{metric(payload, 'CAL_SRM', 'missing_codes', 'max'):.0f}",
        ),
        command("SrmSndrGain", f"{srm_sndr_gain:.3f}"),
        command("SrmInlReduction", f"{srm_inl_reduction:.3f}"),
        command(
            "OracleSndrMedian",
            f"{metric(payload, 'ORACLE_SRM', 'dynamic_sndr_db', 'median'):.3f}",
        ),
    ]
    return "\n".join(lines) + "\n"


def generate_dynamic_table(payload: dict) -> str:
    labels = {
        "NOMINAL_NO_SRM": "Nominal, no SRM",
        "CAL_NO_SRM": "Foreground calibration",
        "CAL_SRM": "Calibration + SRM",
        "ORACLE_SRM": "Physical oracle + SRM",
    }
    rows = []
    for decoder, label in labels.items():
        rows.append(
            "{} & {:.3f} & {:.3f} & {:.3f} & {:.3f} & {:.3f} \\\\".format(
                label,
                metric(payload, decoder, "dynamic_sndr_db", "p01"),
                metric(payload, decoder, "dynamic_sndr_db", "median"),
                metric(payload, decoder, "dynamic_sndr_db", "p99"),
                metric(payload, decoder, "dynamic_sfdr_db", "median"),
                metric(payload, decoder, "dynamic_enob", "median"),
            )
        )
    return "\\newcommand{\\DynamicTableRows}{%\n" + "\n".join(rows) + "\n}\n"


def generate_static_table(payload: dict) -> str:
    labels = {
        "NOMINAL_NO_SRM": "Nominal, no SRM",
        "CAL_NO_SRM": "Foreground calibration",
        "CAL_SRM": "Calibration + SRM",
        "ORACLE_SRM": "Physical oracle + SRM",
    }
    rows = []
    for decoder, label in labels.items():
        rows.append(
            "{} & {:.3f} & {:.3f} & {:.3f} & {:.3f} & {:.0f} & {:.0f} \\\\".format(
                label,
                metric(payload, decoder, "inl_pp_lsb", "median"),
                metric(payload, decoder, "inl_pp_lsb", "p95"),
                metric(payload, decoder, "dnl_pp_lsb", "median"),
                metric(payload, decoder, "dnl_pp_lsb", "p95"),
                metric(payload, decoder, "missing_codes", "median"),
                metric(payload, decoder, "missing_codes", "max"),
            )
        )
    return "\\newcommand{\\StaticTableRows}{%\n" + "\n".join(rows) + "\n}\n"


def generate_representative_table(payload: dict) -> str:
    rows = []
    labels = {"best": "Best", "median": "Median", "worst": "Worst"}
    reps = payload["representative_high_resolution"]
    for key in ("best", "median", "worst"):
        entry = reps[key]
        cal = next(
            item for item in entry["metrics"] if item["decoder"] == "CAL_SRM"
        )
        rows.append(
            "{} & {} & {:.3f} & {:.3f} & {:.3f} & {} \\\\".format(
                labels[key],
                entry["chip_id"],
                cal["dynamic_sndr_db"],
                cal["inl_pp_lsb"],
                cal["dnl_pp_lsb"],
                cal["missing_codes"],
            )
        )
    return (
        "\\newcommand{\\RepresentativeTableRows}{%\n"
        + "\n".join(rows)
        + "\n}\n"
    )


def main() -> None:
    payload = json.loads(SUMMARY_PATH.read_text(encoding="utf-8"))
    if payload.get("status") != "complete" or payload.get("completed_chips") != 512:
        raise RuntimeError("The formal 512-point campaign is not complete.")
    (REPORT_DIR / "generated_metrics.tex").write_text(
        generate_metrics(payload), encoding="utf-8"
    )
    (REPORT_DIR / "dynamic_table_rows.tex").write_text(
        generate_dynamic_table(payload), encoding="utf-8"
    )
    (REPORT_DIR / "static_table_rows.tex").write_text(
        generate_static_table(payload), encoding="utf-8"
    )
    (REPORT_DIR / "representative_table_rows.tex").write_text(
        generate_representative_table(payload), encoding="utf-8"
    )
    print(f"Generated report assets from {SUMMARY_PATH}")


if __name__ == "__main__":
    main()

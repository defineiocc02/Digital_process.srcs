"""Generate LaTeX report assets from calibration validation evidence."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SUMMARY_PATH = ROOT / "outputs" / "summary.json"
REPORT_DIR = ROOT / "report"


def esc(text: str) -> str:
    return text.replace("_", r"\_")


def metric(summary: dict, decoder: str, field: str, stat: str = "median") -> float:
    return float(summary[decoder][field][stat])


def macro(name: str, value: str | float) -> str:
    if isinstance(value, float):
        text = f"{value:.3f}"
    else:
        text = value
    return rf"\newcommand{{\{name}}}{{{text}}}"


def build_assets() -> None:
    payload = json.loads(SUMMARY_PATH.read_text(encoding="utf-8"))
    summary = payload["summary"]
    REPORT_DIR.mkdir(parents=True, exist_ok=True)

    lines = [
        "% Auto-generated from analysis/calibration_effectiveness_20260729/outputs/summary.json",
        macro("ValNChips", str(payload["config"]["n_chips"])),
        macro("ValFFT", str(payload["config"]["n_fft"])),
        macro("ValFinHz", f"{payload['coherent_input']['fin_hz']:.3f}"),
        macro("ValBin", str(payload["coherent_input"]["fft_bin"])),
        macro("NominalSndrMed", metric(summary, "NOMINAL", "dynamic_sndr_db")),
        macro("CalRawSndrMed", metric(summary, "RTL_CAL_RAW", "dynamic_sndr_db")),
        macro("CalGainSndrMed", metric(summary, "RTL_CAL_GAIN_COMP", "dynamic_sndr_db")),
        macro("OracleSndrMed", metric(summary, "ORACLE", "dynamic_sndr_db")),
        macro("NominalSfdrMed", metric(summary, "NOMINAL", "dynamic_sfdr_db")),
        macro("CalRawSfdrMed", metric(summary, "RTL_CAL_RAW", "dynamic_sfdr_db")),
        macro("CalGainSfdrMed", metric(summary, "RTL_CAL_GAIN_COMP", "dynamic_sfdr_db")),
        macro("OracleSfdrMed", metric(summary, "ORACLE", "dynamic_sfdr_db")),
        macro("NominalWeightRmseMed", metric(summary, "NOMINAL", "weight_rmse_gain_aligned_lsb")),
        macro("CalRawWeightRmseMed", metric(summary, "RTL_CAL_RAW", "weight_rmse_gain_aligned_lsb")),
        macro("CalGainWeightRmseMed", metric(summary, "RTL_CAL_GAIN_COMP", "weight_rmse_gain_aligned_lsb")),
        macro("OracleWeightRmseMed", metric(summary, "ORACLE", "weight_rmse_gain_aligned_lsb")),
        macro("NominalStaticRmsMed", metric(summary, "NOMINAL", "static_error_rms_code")),
        macro("CalRawStaticRmsMed", metric(summary, "RTL_CAL_RAW", "static_error_rms_code")),
        macro("CalGainStaticRmsMed", metric(summary, "RTL_CAL_GAIN_COMP", "static_error_rms_code")),
        macro("OracleStaticRmsMed", metric(summary, "ORACLE", "static_error_rms_code")),
        macro("CalGainVsNominalDb", metric(summary, "RTL_CAL_GAIN_COMP", "dynamic_sndr_db") - metric(summary, "NOMINAL", "dynamic_sndr_db")),
        macro("OracleGapDb", metric(summary, "ORACLE", "dynamic_sndr_db") - metric(summary, "RTL_CAL_GAIN_COMP", "dynamic_sndr_db")),
        macro("CalWeightReduction", metric(summary, "NOMINAL", "weight_rmse_gain_aligned_lsb") / metric(summary, "RTL_CAL_GAIN_COMP", "weight_rmse_gain_aligned_lsb")),
    ]
    (REPORT_DIR / "generated_metrics.tex").write_text("\n".join(lines) + "\n", encoding="utf-8")

    order = ["NOMINAL", "RTL_CAL_RAW", "RTL_CAL_GAIN_COMP", "ORACLE"]
    labels = {
        "NOMINAL": "Nominal",
        "RTL_CAL_RAW": "RTL-equivalent calibration",
        "RTL_CAL_GAIN_COMP": "Calibration + gain alignment",
        "ORACLE": "Physical-weight oracle",
    }
    table = [
        r"\small",
        r"\begin{tabularx}{\linewidth}{@{}>{\raggedright\arraybackslash}Xrrrr@{}}",
        r"\toprule",
        r"Path & SNDR & SFDR & W-RMSE & Static RMS \\",
        r" & dB & dBc & LSB & code \\",
        r"\midrule",
    ]
    for decoder in order:
        table.append(
            f"{labels[decoder]} & "
            f"{metric(summary, decoder, 'dynamic_sndr_db'):.3f} & "
            f"{metric(summary, decoder, 'dynamic_sfdr_db'):.3f} & "
            f"{metric(summary, decoder, 'weight_rmse_gain_aligned_lsb'):.4f} & "
            f"{metric(summary, decoder, 'static_error_rms_code'):.4f} \\\\"
        )
    table.extend([r"\bottomrule", r"\end{tabularx}"])
    (REPORT_DIR / "summary_table.tex").write_text("\n".join(table) + "\n", encoding="utf-8")


if __name__ == "__main__":
    build_assets()

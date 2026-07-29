"""Run the complete 512-point SAR ADC behavioral campaign.

The runner is checkpointed per chip. Re-running the same command resumes from
completed JSON checkpoints unless ``--no-resume`` is supplied.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import asdict, replace
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple

import matplotlib.pyplot as plt
import numpy as np

plt.rcParams["pdf.fonttype"] = 42
plt.rcParams["ps.fonttype"] = 42

try:
    from .full_sar_model import (
        DECODER_ORDER,
        DecoderMetrics,
        FullSarConfig,
        evaluate_chip,
        metrics_to_dict,
        summarize,
    )
except ImportError:  # Direct script execution.
    from full_sar_model import (
        DECODER_ORDER,
        DecoderMetrics,
        FullSarConfig,
        evaluate_chip,
        metrics_to_dict,
        summarize,
    )


ROOT = Path(__file__).resolve().parent
DEFAULT_OUTDIR = ROOT / "outputs"


def _checkpoint_path(outdir: Path, chip_id: int) -> Path:
    return outdir / "checkpoints" / f"chip_{chip_id:04d}.json"


def _evaluate_worker(
    chip_id: int,
    cfg: FullSarConfig,
) -> Tuple[int, List[Dict[str, object]], Dict[str, object]]:
    metrics, trace = evaluate_chip(chip_id, cfg)
    # Keep detailed traces for the first three chips only in the main campaign.
    if chip_id >= 3:
        trace = {
            "chip_id": chip_id,
            "fin_hz": trace["fin_hz"],
            "fft_bin": trace["fft_bin"],
            "srm": trace["srm"],
        }
    return chip_id, [metrics_to_dict(item) for item in metrics], trace


def _write_checkpoint(
    path: Path,
    chip_id: int,
    metrics: List[Dict[str, object]],
    trace: Dict[str, object],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(
        json.dumps(
            {"chip_id": chip_id, "metrics": metrics, "trace": trace},
            indent=2,
        ),
        encoding="utf-8",
    )
    temporary.replace(path)


def _load_checkpoint(path: Path) -> Tuple[List[Dict[str, object]], Dict[str, object]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return payload["metrics"], payload["trace"]


def _write_progress(
    outdir: Path,
    cfg: FullSarConfig,
    completed: int,
    started_at: float,
) -> None:
    elapsed = time.time() - started_at
    rate = completed / elapsed if elapsed > 0.0 else 0.0
    remaining = max(cfg.n_chips - completed, 0)
    eta = remaining / rate if rate > 0.0 else None
    payload = {
        "requested_chips": cfg.n_chips,
        "completed_chips": completed,
        "elapsed_seconds": elapsed,
        "chips_per_second": rate,
        "estimated_remaining_seconds": eta,
        "status": "complete" if completed == cfg.n_chips else "running",
    }
    (outdir / "progress.json").write_text(
        json.dumps(payload, indent=2), encoding="utf-8"
    )


def _rows_to_metrics(rows: Iterable[Dict[str, object]]) -> List[DecoderMetrics]:
    return [DecoderMetrics(**row) for row in rows]


def aggregate(metrics: Sequence[DecoderMetrics]) -> Dict[str, object]:
    fields = [
        "dynamic_sndr_db",
        "dynamic_snr_db",
        "dynamic_sfdr_db",
        "dynamic_thd_db",
        "dynamic_enob",
        "dnl_min_lsb",
        "dnl_max_lsb",
        "dnl_pp_lsb",
        "inl_min_lsb",
        "inl_max_lsb",
        "inl_pp_lsb",
        "missing_codes",
        "saturation_fraction",
        "weight_rmse_gain_aligned_lsb",
        "srm_nonzero_fraction",
        "srm_count_mean",
    ]
    summary: Dict[str, object] = {}
    for decoder in DECODER_ORDER:
        subset = [item for item in metrics if item.decoder == decoder]
        summary[decoder] = {
            "n_chips": len(subset),
            **{
                field: summarize(float(getattr(item, field)) for item in subset)
                for field in fields
            },
        }
    return summary


def write_csv(metrics: Sequence[DecoderMetrics], path: Path) -> None:
    rows = [metrics_to_dict(item) for item in metrics]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def plot_summary(summary: Dict[str, object], outdir: Path) -> None:
    labels = {
        "NOMINAL_NO_SRM": "Nominal",
        "CAL_NO_SRM": "Calibration",
        "CAL_SRM": "Calibration + SRM",
        "ORACLE_SRM": "Oracle + SRM",
    }
    colors = ["#697783", "#277da1", "#2a9d6f", "#6d5aa8"]
    x = np.arange(len(DECODER_ORDER))

    def median(decoder: str, metric: str) -> float:
        return float(summary[decoder][metric]["median"])  # type: ignore[index]

    plt.figure(figsize=(9.0, 5.0))
    plt.bar(
        x,
        [median(name, "dynamic_sndr_db") for name in DECODER_ORDER],
        color=colors,
    )
    plt.xticks(x, [labels[name] for name in DECODER_ORDER])
    plt.ylabel("SNDR median (dB)")
    plt.title("512-point full-loop dynamic decoding")
    plt.grid(axis="y", alpha=0.25)
    plt.tight_layout()
    plt.savefig(outdir / "fig_sndr_summary.png", dpi=200)
    plt.savefig(outdir / "fig_sndr_summary.pdf")
    plt.close()

    plt.figure(figsize=(9.0, 5.0))
    plt.bar(
        x,
        [median(name, "inl_pp_lsb") for name in DECODER_ORDER],
        color=colors,
    )
    plt.xticks(x, [labels[name] for name in DECODER_ORDER])
    plt.ylabel("Endpoint INL p-p median (LSB)")
    plt.title("512-point full-range ramp linearity")
    plt.grid(axis="y", alpha=0.25)
    plt.tight_layout()
    plt.savefig(outdir / "fig_inl_summary.png", dpi=200)
    plt.savefig(outdir / "fig_inl_summary.pdf")
    plt.close()

    plt.figure(figsize=(9.0, 5.0))
    missing_values = [
        median(name, "missing_codes") + 1.0 for name in DECODER_ORDER
    ]
    plt.bar(
        x,
        missing_values,
        color=colors,
    )
    plt.xticks(x, [labels[name] for name in DECODER_ORDER])
    plt.ylabel("Missing-code median + 1")
    plt.yscale("log")
    plt.title("512-point missing-code comparison")
    plt.grid(axis="y", alpha=0.25)
    plt.tight_layout()
    plt.savefig(outdir / "fig_missing_codes_summary.png", dpi=200)
    plt.savefig(outdir / "fig_missing_codes_summary.pdf")
    plt.close()


def run_representative_high_resolution(
    cfg: FullSarConfig,
    metrics: Sequence[DecoderMetrics],
    outdir: Path,
) -> Dict[str, object]:
    cal = sorted(
        (item for item in metrics if item.decoder == "CAL_SRM"),
        key=lambda item: item.inl_pp_lsb,
    )
    selected = {
        "best": cal[0].chip_id,
        "median": cal[len(cal) // 2].chip_id,
        "worst": cal[-1].chip_id,
    }
    representative: Dict[str, object] = {}
    for label, chip_id in selected.items():
        highres_metrics, trace = evaluate_chip(
            chip_id,
            cfg,
            static_samples_per_code=cfg.representative_samples_per_code,
            retain_linearity_arrays=True,
        )
        retained = trace.pop("retained")
        representative[label] = {
            "chip_id": chip_id,
            "metrics": [metrics_to_dict(item) for item in highres_metrics],
            "trace": trace,
        }
        for decoder in ("NOMINAL_NO_SRM", "CAL_SRM", "ORACLE_SRM"):
            linearity = retained[decoder]["linearity"]
            np.savez_compressed(
                outdir / f"highres_{label}_{decoder.lower()}.npz",
                code=linearity["code"],
                dnl=linearity["dnl"],
                transition_code=linearity["transition_code"],
                inl=linearity["inl"],
            )
        plot_representative_linearity(label, chip_id, retained, outdir)
        plot_representative_spectrum(label, chip_id, retained, cfg, outdir)
    return representative


def plot_representative_linearity(
    label: str,
    chip_id: int,
    retained: Dict[str, object],
    outdir: Path,
) -> None:
    fig, axes = plt.subplots(2, 3, figsize=(14.0, 7.0), sharex="col")
    styles = {
        "NOMINAL_NO_SRM": ("Nominal", "#697783"),
        "CAL_SRM": ("Calibration + SRM", "#2a9d6f"),
        "ORACLE_SRM": ("Oracle + SRM", "#6d5aa8"),
    }
    for column, (decoder, (display, color)) in enumerate(styles.items()):
        linearity = retained[decoder]["linearity"]
        axes[0, column].plot(
            linearity["code"],
            linearity["dnl"],
            color=color,
            linewidth=0.7,
        )
        axes[1, column].plot(
            linearity["transition_code"],
            linearity["inl"],
            color=color,
            linewidth=0.7,
        )
        axes[0, column].set_title(display)
        axes[1, column].set_xlabel("Signed output code")
    axes[0, 0].set_ylabel("DNL (LSB)")
    axes[1, 0].set_ylabel("INL (LSB)")
    fig.suptitle(
        f"{label.title()} CAL_SRM chip {chip_id}: "
        "8 samples/code high-resolution cross-check",
        y=0.995,
    )
    for axis in axes.flat:
        axis.grid(alpha=0.2)
    fig.tight_layout(rect=(0.0, 0.0, 1.0, 0.97))
    fig.savefig(outdir / f"fig_highres_{label}_dnl_inl.png", dpi=200)
    fig.savefig(outdir / f"fig_highres_{label}_dnl_inl.pdf")
    plt.close(fig)


def plot_representative_spectrum(
    label: str,
    chip_id: int,
    retained: Dict[str, object],
    cfg: FullSarConfig,
    outdir: Path,
) -> None:
    styles = {
        "NOMINAL_NO_SRM": ("Nominal", "#697783"),
        "CAL_SRM": ("Calibration + SRM", "#2a9d6f"),
        "ORACLE_SRM": ("Oracle + SRM", "#6d5aa8"),
    }
    plt.figure(figsize=(10.0, 5.5))
    for decoder, (display, color) in styles.items():
        codes = np.asarray(retained[decoder]["sine_codes"], dtype=float)
        codes -= np.mean(codes)
        magnitude = np.abs(np.fft.rfft(codes))
        magnitude /= max(float(np.max(magnitude)), np.finfo(float).tiny)
        spectrum_db = 20.0 * np.log10(
            np.maximum(magnitude, np.finfo(float).tiny)
        )
        frequency = np.fft.rfftfreq(len(codes), d=1.0 / cfg.fs_hz)
        plt.plot(
            frequency / 1.0e6,
            spectrum_db,
            label=display,
            color=color,
            linewidth=0.8,
        )
    plt.xlim(0.0, cfg.fs_hz / 2.0e6)
    plt.ylim(-150.0, 5.0)
    plt.xlabel("Frequency (MHz)")
    plt.ylabel("Magnitude (dBc)")
    plt.title(f"{label.title()} CAL_SRM chip {chip_id}: coherent FFT")
    plt.grid(alpha=0.2)
    plt.legend()
    plt.tight_layout()
    plt.savefig(outdir / f"fig_highres_{label}_spectrum.png", dpi=200)
    plt.savefig(outdir / f"fig_highres_{label}_spectrum.pdf")
    plt.close()


def print_summary(summary: Dict[str, object]) -> None:
    print("\n=== Full SAR behavioral campaign summary ===")
    for decoder in DECODER_ORDER:
        item = summary[decoder]  # type: ignore[index]
        print(
            f"{decoder:18s} "
            f"SNDR_med={item['dynamic_sndr_db']['median']:8.3f} dB "
            f"SFDR_med={item['dynamic_sfdr_db']['median']:8.3f} dBc "
            f"INLpp_med={item['inl_pp_lsb']['median']:8.3f} LSB "
            f"DNLpp_med={item['dnl_pp_lsb']['median']:8.3f} LSB "
            f"missing_med={item['missing_codes']['median']:7.1f}"
        )


def run_campaign(
    cfg: FullSarConfig,
    outdir: Path,
    workers: int,
    resume: bool,
) -> Dict[str, object]:
    cfg.validate()
    outdir.mkdir(parents=True, exist_ok=True)
    started_at = time.time()
    all_rows: List[Dict[str, object]] = []
    traces: Dict[str, object] = {}
    pending: List[int] = []

    for chip_id in range(cfg.n_chips):
        checkpoint = _checkpoint_path(outdir, chip_id)
        if resume and checkpoint.exists():
            rows, trace = _load_checkpoint(checkpoint)
            all_rows.extend(rows)
            if chip_id < 3:
                traces[f"chip_{chip_id}"] = trace
        else:
            pending.append(chip_id)

    completed = cfg.n_chips - len(pending)
    _write_progress(outdir, cfg, completed, started_at)
    print(
        f"Campaign: requested={cfg.n_chips}, resumed={completed}, "
        f"pending={len(pending)}, workers={workers}"
    )

    if pending:
        with ProcessPoolExecutor(max_workers=workers) as executor:
            future_map = {
                executor.submit(_evaluate_worker, chip_id, cfg): chip_id
                for chip_id in pending
            }
            for future in as_completed(future_map):
                chip_id, rows, trace = future.result()
                _write_checkpoint(
                    _checkpoint_path(outdir, chip_id), chip_id, rows, trace
                )
                all_rows.extend(rows)
                if chip_id < 3:
                    traces[f"chip_{chip_id}"] = trace
                completed += 1
                _write_progress(outdir, cfg, completed, started_at)
                if completed == cfg.n_chips or completed % 8 == 0:
                    print(f"Completed {completed}/{cfg.n_chips} chips", flush=True)

    all_rows.sort(key=lambda row: (int(row["chip_id"]), str(row["decoder"])))
    metrics = _rows_to_metrics(all_rows)
    summary = aggregate(metrics)
    write_csv(metrics, outdir / "per_chip_decoder_metrics.csv")
    plot_summary(summary, outdir)
    representative = run_representative_high_resolution(cfg, metrics, outdir)
    checkpoint_files = sorted((outdir / "checkpoints").glob("chip_*.json"))
    checkpoint_span_seconds = 0.0
    if checkpoint_files:
        mtimes = [path.stat().st_mtime for path in checkpoint_files]
        checkpoint_span_seconds = max(mtimes) - min(mtimes)

    payload = {
        "status": "complete",
        "scope": (
            "Complete system-level behavioral SAR loop with sampling noise, "
            "20 signed decisions, current foreground calibration, 22-decision "
            "SRM, RTL Q8 reconstruction, FFT, and ramp-histogram DNL/INL."
        ),
        "source_of_truth": {
            "foreground_calibration": "rtl/sar_calib_ctrl_serial.sv",
            "srm_lut": "rtl/srm_residue_estimator.sv",
            "q8_reconstruction": "rtl/sar_reconstruction.sv",
            "metrics_backend": "ADCToolbox 0.9.1 (MIT), commit a8995cf4",
        },
        "evidence_boundary": (
            "Behavioral system validation only. It does not sign off transistor "
            "noise, CDAC charge redistribution, reference settling, PVT, PEX, "
            "metastability timing, or silicon yield."
        ),
        "config": asdict(cfg),
        "completed_chips": cfg.n_chips,
        "decoder_rows": len(metrics),
        "summary": summary,
        "representative_high_resolution": representative,
        "trace_excerpt": traces,
        "checkpoint_span_seconds": checkpoint_span_seconds,
        "aggregation_runtime_seconds": time.time() - started_at,
    }
    (outdir / "summary.json").write_text(
        json.dumps(payload, indent=2), encoding="utf-8"
    )
    print_summary(summary)
    print(f"Artifacts: {outdir}")
    return payload


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--outdir", type=Path, default=DEFAULT_OUTDIR)
    parser.add_argument("--chips", type=int, default=512)
    parser.add_argument("--workers", type=int, default=max(1, min(8, (os.cpu_count() or 2) // 2)))
    parser.add_argument("--no-resume", action="store_true")
    parser.add_argument("--quick", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    cfg = FullSarConfig(n_chips=args.chips)
    if args.quick:
        cfg = replace(
            cfg,
            n_chips=min(args.chips, 4),
            n_fft=2048,
            static_samples_per_code=1,
            representative_samples_per_code=2,
        )
    run_campaign(
        cfg=cfg,
        outdir=args.outdir,
        workers=max(1, args.workers),
        resume=not args.no_resume,
    )


if __name__ == "__main__":
    main()

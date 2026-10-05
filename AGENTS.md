# Metric evidence contract

For current ADC metrics, use `docs/METRICS_CURRENT.json` and
`analysis.metric_evidence.load_current_metrics()` (or `python -m
analysis.metric_evidence`). Do not pick the newest directory, glob `summary.json`,
or treat old `outputs` / `outputs_revalidation` / delivery copies as current.

Only `physical_cdac.ideal` and `physical_cdac.main` have permanent current
machine-readable evidence. Missing scopes must fail; do not substitute old
full-SAR, self-calibration, sigma/amplitude or ablation tables. A current result
must keep its evidence ID, metric definition, conditions and provenance.

Historical JSON/CSV/NPZ/PDF/TeX and delivery/archive packages are frozen. Do not
rewrite their numbers or refresh their checksum lists. Historical report
reproduction requires `--historical-evidence --outdir NEW_DIRECTORY`; those
outputs must be labelled historical and the spectral erratum still applies.
Campaign producers retain legacy output defaults: always pass a fresh `--outdir`
when rerunning, and use `--no-resume` for the full-SAR campaign.

Run `python -m pytest analysis/test_metric_evidence.py -q` and
`python scripts/check_repo_consistency.py` before publishing metric-related edits.
See `docs/METRIC_ENTRYPOINT_AUDIT_20261005.md` for coverage and limitations.

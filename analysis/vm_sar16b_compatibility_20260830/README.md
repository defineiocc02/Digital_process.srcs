# VM SAR16B Compatibility Audit

Read first:

- `SAR16B_RTL_COMPATIBILITY_REPORT_CN.md`: full Chinese engineering report.
- `compatibility_matrix.csv`: component-by-component direct-use decision and priority.
- `local_rtl_validation_summary.json`: XSIM and Vivado synthesis evidence from 2026-08-30.

Authoritative live-VM evidence:

- `checkpoint_sar16b_series.json`: SAR16B library and cell inventory.
- `checkpoint_sar16b_hierarchy.json`: cross-library OA hierarchy and connectivity.
- `checkpoint_sar16b_full_params.json`: unfiltered instance/CDF parameters.
- `checkpoint_text_views.json`: remote HDL file hashes and exported-file manifest.
- `checkpoint_sar16b_maestro.json`: current Maestro setup captured read-only.
- `checkpoint_sar16b_history_logs.json`: existing Maestro history-log status.

Primary collection tools:

- `inspect_sar16b_series.py`
- `read_sar16b_series_hierarchy.py`
- `read_sar16b_full_params.py`
- `export_sar16b_text_views.py`
- `read_sar16b_maestro.py`
- `collect_sar16b_history_logs.py`

The other `checkpoint_*` and helper scripts are preliminary discovery checkpoints retained for traceability. `bridge_session.env`, generated HDL snapshots, temporary remote files, and Python caches are intentionally ignored. This folder contains no VM password or private key.

Scope: this was a read-only compatibility audit. It did not modify the VM schematic or claim a passing mixed-signal simulation.

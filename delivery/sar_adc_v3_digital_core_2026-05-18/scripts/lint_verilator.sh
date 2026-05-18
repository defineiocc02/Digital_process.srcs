#!/usr/bin/env bash
set -euo pipefail

echo "== SAR ADC V3 RTL lint =="

RTL_FILES=(
  "rtl/sar_calib_ctrl_serial.sv"
  "rtl/sar_reconstruction.sv"
  "rtl/srm_residue_estimator.sv"
  "rtl/sar_calib_fpga_top.sv"
  "rtl/sar_adc_digital_top.sv"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

for f in "${RTL_FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: missing RTL file: $f"
    exit 1
  fi
done

verilator --version

# --lint-only:  syntax/static lint only, no simulation build.
# -sv:          SystemVerilog mode.
# -Wall:        broad warning coverage.
# -Wno-fatal:   collect warnings without stopping immediately.
#               Warnings are informational at this stage;
#               a dedicated waiver/cleanup round follows separately.
verilator \
  --lint-only \
  -sv \
  -Wall \
  -Wno-fatal \
  "${RTL_FILES[@]}"

echo "== Verilator lint completed =="

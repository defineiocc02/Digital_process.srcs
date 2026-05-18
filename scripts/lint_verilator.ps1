$ErrorActionPreference = "Stop"

Write-Host "== SAR ADC V3 RTL lint =="

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Resolve-Path (Join-Path $ScriptDir "..")
Set-Location $RootDir

$RtlFiles = @(
    "rtl/sar_calib_ctrl_serial.sv",
    "rtl/sar_reconstruction.sv",
    "rtl/srm_residue_estimator.sv",
    "rtl/sar_calib_fpga_top.sv",
    "rtl/sar_adc_digital_top.sv"
)

foreach ($f in $RtlFiles) {
    if (!(Test-Path $f)) {
        throw "Missing RTL file: $f"
    }
}

verilator --version

# --lint-only:  syntax/static lint only, no simulation build.
# -sv:          SystemVerilog mode.
# -Wall:        broad warning coverage.
# -Wno-fatal:   collect warnings without stopping immediately.

& verilator `
    --lint-only `
    -sv `
    -Wall `
    -Wno-fatal `
    @RtlFiles

if ($LASTEXITCODE -ne 0) {
    throw "Verilator lint failed with exit code $LASTEXITCODE"
}

Write-Host "== Verilator lint completed =="

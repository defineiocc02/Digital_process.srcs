param(
    [string] $VivadoBin = 'D:\Academic\Vivado2018\Vivado\2018.3\bin',
    [string] $Part = 'xc7a35tfgg484-2'
)

$ErrorActionPreference = 'Stop'

$PackageRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Vivado = Join-Path $VivadoBin 'vivado.bat'
$TclScript = Join-Path $PSScriptRoot 'synth_one_top.tcl'

if (-not (Test-Path -LiteralPath $Vivado)) {
    throw "Vivado batch executable not found: $Vivado"
}

$checks = @(
    @{
        Top = 'sar_reconstruction'
        Files = @('rtl/sar_reconstruction.sv')
    },
    @{
        Top = 'srm_residue_estimator'
        Files = @('rtl/srm_residue_estimator.sv')
    },
    @{
        Top = 'sar_calib_ctrl_serial'
        Files = @('rtl/sar_calib_ctrl_serial.sv')
    }
)

foreach ($check in $checks) {
    $top = $check.Top
    $outDir = Join-Path $PackageRoot "sim_work/synth/$top"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    & $Vivado -mode batch -source $TclScript -tclargs $PackageRoot $Part $top $outDir @($check.Files)
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado synthesis failed for $top with exit code $LASTEXITCODE"
    }
}

Write-Host "PACKAGE SYNTH_CHECK OVERALL RESULT : PASS"

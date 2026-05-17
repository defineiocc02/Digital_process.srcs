param(
    [string] $VivadoBin = 'D:\Academic\Vivado2018\Vivado\2018.3\bin',
    [string] $Part = 'xc7a35tfgg484-2'
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Vivado = Join-Path $VivadoBin 'vivado.bat'
$TclScript = Join-Path $PSScriptRoot 'synth_one_top.tcl'

if (-not (Test-Path -LiteralPath $Vivado)) {
    throw "Vivado batch executable not found: $Vivado"
}

if (-not (Test-Path -LiteralPath $TclScript)) {
    throw "Synthesis Tcl script not found: $TclScript"
}

$checks = @(
    @{
        Top = 'sar_reconstruction'
        Files = @(
            'Digital_process/Digital_process.srcs/sources_1/new/sar_reconstruction.sv'
        )
    },
    @{
        Top = 'srm_residue_estimator'
        Files = @(
            'Digital_process/Digital_process.srcs/sources_1/new/srm_residue_estimator.sv'
        )
    },
    @{
        Top = 'sar_calib_ctrl_serial'
        Files = @(
            'Digital_process/Digital_process.srcs/sources_1/new/sar_calib_ctrl_serial.sv'
        )
    }
)

foreach ($check in $checks) {
    $top = $check.Top
    $outDir = Join-Path $RepoRoot "sim_work/synth/$top"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    Write-Host ""
    Write-Host "================================================================"
    Write-Host "Synthesizing $top"
    Write-Host "================================================================"

    & $Vivado -mode batch -source $TclScript -tclargs $RepoRoot $Part $top $outDir @($check.Files)
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado synthesis failed for $top with exit code $LASTEXITCODE"
    }
}

Write-Host ""
Write-Host "SYNTH_CHECK OVERALL RESULT : PASS"

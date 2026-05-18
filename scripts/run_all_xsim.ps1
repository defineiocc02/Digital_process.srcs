param(
    [string] $VivadoBin = 'D:\Academic\Vivado2018\Vivado\2018.3\bin'
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Runner = Join-Path $PSScriptRoot 'run_xsim.ps1'

if (-not (Test-Path -LiteralPath $Runner)) {
    throw "XSIM runner not found: $Runner"
}

if ((Test-Path -LiteralPath (Join-Path $RepoRoot 'rtl')) -and
    (Test-Path -LiteralPath (Join-Path $RepoRoot 'tb'))) {
    Write-Host "XSIM source layout : delivery package"
    $tests = @(
        @{
            Top = 'tb_sar_recon'
            Files = @(
                'rtl/sar_reconstruction.sv',
                'tb/tb_sar_recon.sv'
            )
        },
        @{
            Top = 'tb_srm_residue_estimator'
            Files = @(
                'rtl/srm_residue_estimator.sv',
                'tb/tb_srm_residue_estimator.sv'
            )
        },
        @{
            Top = 'tb_gain_comp_check_lsb'
            Files = @(
                'rtl/sar_calib_ctrl_serial.sv',
                'tb/tb_gain_comp_check_lsb.sv'
            )
        }
    )
} else {
    Write-Host "XSIM source layout : active Vivado repository"
    $tests = @(
        @{
            Top = 'tb_sar_recon'
            Files = @(
                'Digital_process/Digital_process.srcs/sources_1/new/sar_reconstruction.sv',
                'Digital_process/Digital_process.srcs/sim_1/new/tb_sar_recon.sv'
            )
        },
        @{
            Top = 'tb_srm_residue_estimator'
            Files = @(
                'Digital_process/Digital_process.srcs/sources_1/new/srm_residue_estimator.sv',
                'Digital_process/Digital_process.srcs/sim_1/new/tb_srm_residue_estimator.sv'
            )
        },
        @{
            Top = 'tb_gain_comp_check_lsb'
            Files = @(
                'Digital_process/Digital_process.srcs/sources_1/new/sar_calib_ctrl_serial.sv',
                'Digital_process/Digital_process.srcs/sim_1/new/tb_gain_comp_check_lsb.sv'
            )
        }
    )
}

foreach ($test in $tests) {
    $top = $test.Top
    $workDir = Join-Path $RepoRoot "sim_work/$top"
    $files = @($test.Files | ForEach-Object { Join-Path $RepoRoot $_ })

    Write-Host ""
    Write-Host "================================================================"
    Write-Host "Running XSIM $top"
    Write-Host "================================================================"

    & $Runner `
        -VivadoBin $VivadoBin `
        -WorkDir $workDir `
        -Top $top `
        -Files $files

    if ($LASTEXITCODE -ne 0) {
        throw "XSIM failed for $top with exit code $LASTEXITCODE"
    }
}

Write-Host ""
Write-Host "XSIM OVERALL RESULT : PASS"

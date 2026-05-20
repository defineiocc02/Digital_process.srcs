param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("build_calib_core", "build_recon_core", "build_fpga_demo", "build_asic_skeleton")]
    [string]$Target
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Resolve-Path (Join-Path $ScriptDir "..")

# Vivado location: honour XILINX_VIVADO env var, then PATH, then default
if ($env:XILINX_VIVADO) {
    $VivadoExe = Join-Path $env:XILINX_VIVADO "bin" "vivado.bat"
} elseif (Get-Command "vivado" -ErrorAction SilentlyContinue) {
    $VivadoExe = "vivado"
} else {
    $VivadoExe = "D:\Academic\Vivado2018\Vivado\2018.3\bin\vivado.bat"
}

if (-not (Test-Path -LiteralPath $VivadoExe)) {
    throw "Vivado batch executable not found: $VivadoExe`nSet `$env:XILINX_VIVADO to the Vivado installation root."
}

$BuildTcl = Join-Path $ScriptDir "build_vivado.tcl"
if (-not (Test-Path -LiteralPath $BuildTcl)) {
    throw "Build TCL script not found: $BuildTcl"
}

Write-Host "BUILD_TARGET = $Target"
Write-Host "Vivado       = $VivadoExe"
Write-Host "Repo root    = $RootDir"

$env:BUILD_TARGET = $Target

& $VivadoExe -mode batch -source $BuildTcl

if ($LASTEXITCODE -ne 0) {
    throw "Vivado build failed with exit code $LASTEXITCODE"
}

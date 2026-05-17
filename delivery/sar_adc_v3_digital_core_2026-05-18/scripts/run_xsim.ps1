param(
    [Parameter(Mandatory=$true)] [string] $VivadoBin,
    [Parameter(Mandatory=$true)] [string] $WorkDir,
    [Parameter(Mandatory=$true)] [string] $Top,
    [string] $Snapshot,
    [Parameter(Mandatory=$true)] [string[]] $Files
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Snapshot)) {
    $Snapshot = "${Top}_sim"
}

$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim  = Join-Path $VivadoBin 'xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Vivado simulator tool not found: $tool"
    }
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Push-Location $WorkDir
try {
    & $xvlog -sv @Files
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & $xelab $Top -debug typical -s $Snapshot
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & $xsim $Snapshot -runall
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Pop-Location
}

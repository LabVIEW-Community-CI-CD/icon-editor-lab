#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$UbuntuManifestPath,
    [string]$Scenario = 'ok',
    [string]$WindowsRunRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $env:WORKSPACE_ROOT
if (-not $root) {
    $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..') -ErrorAction Stop).ProviderPath
}

Write-Host "[handshake-sim] WorkspaceRoot: $root" -ForegroundColor DarkGray

if (-not $UbuntuManifestPath) {
    $ubuntuRoot = Join-Path $root 'out/local-ci-ubuntu'
    if (-not (Test-Path -LiteralPath $ubuntuRoot -PathType Container)) {
        throw "[handshake-sim] No Ubuntu local-ci directory found at '$ubuntuRoot'. Provide -UbuntuManifestPath explicitly."
    }
    $latestDir = Get-ChildItem -LiteralPath $ubuntuRoot -Directory |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if (-not $latestDir) {
        throw "[handshake-sim] No Ubuntu run directories found under '$ubuntuRoot'."
    }
    $UbuntuManifestPath = Join-Path $latestDir.FullName 'ubuntu-run.json'
}

$UbuntuManifestPath = (Resolve-Path -LiteralPath $UbuntuManifestPath -ErrorAction Stop).ProviderPath

if (-not $WindowsRunRoot) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $WindowsRunRoot = Join-Path $root "out/local-ci-sim/$stamp"
} else {
    $resolved = Resolve-Path -LiteralPath $WindowsRunRoot -ErrorAction SilentlyContinue
    if ($resolved) {
        $WindowsRunRoot = $resolved.ProviderPath
    }
}

Write-Host "[handshake-sim] Ubuntu manifest : $UbuntuManifestPath" -ForegroundColor DarkGray
Write-Host "[handshake-sim] Windows run root: $WindowsRunRoot" -ForegroundColor DarkGray
Write-Host "[handshake-sim] Scenario        : $Scenario" -ForegroundColor DarkGray

$xCliProject = Join-Path $root 'tools/x-cli-develop/src/XCli/XCli.csproj'
if (-not (Test-Path -LiteralPath $xCliProject -PathType Leaf)) {
    throw "[handshake-sim] XCli project not found at '$xCliProject'. Ensure tools/x-cli-develop is present."
}

$dotnetCmd = Get-Command dotnet -ErrorAction Stop

$payloadArgs = @(
    'localci-handshake',
    '--ubuntu-manifest', $UbuntuManifestPath,
    '--windows-run-root', $WindowsRunRoot,
    '--scenario', $Scenario
)

Write-Host "[handshake-sim] Invoking x-cli handshake simulation..." -ForegroundColor Cyan

& $dotnetCmd.Source run --project $xCliProject -- @payloadArgs
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    throw "[handshake-sim] x-cli localci-handshake exited with code $exitCode."
}

Write-Host "[handshake-sim] Simulation completed. Windows run root: $WindowsRunRoot" -ForegroundColor Green

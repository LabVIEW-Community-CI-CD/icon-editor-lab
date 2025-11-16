#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$StagePath,
    [string]$StageChannel,
    [string]$WorkDir,
    [switch]$RunLabVIEWSmoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param([string]$Root)
    if ([string]::IsNullOrWhiteSpace($Root)) {
        return (Resolve-Path '.').Path
    }
    return (Get-Item $Root).FullName
}

$RepoRoot = Resolve-RepoRoot -Root $RepoRoot

if (-not $WorkDir) {
    $WorkDir = Join-Path $RepoRoot '.tmp-tests/xcli-release-validation'
}

function Get-RunnerProfileSafe {
    param([string]$Root)

    $modulePath = Join-Path $Root 'src/tools/RunnerProfile.psm1'
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        return $null
    }

    try {
        if (-not (Get-Module -Name RunnerProfile -ErrorAction SilentlyContinue)) {
            Import-Module -Name $modulePath -ErrorAction Stop
        }
        return Get-RunnerProfile -DisableInstrumentation
    } catch {
        Write-Warning ("[[xcli]] RunnerProfile not available: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Resolve-StagedArtifact {
    param(
        [string]$RepoRoot,
        [string]$PathCandidate,
        [string]$Channel
    )

    if ($PathCandidate -and (Test-Path -LiteralPath $PathCandidate -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $PathCandidate).Path
    }

    $envStagePath = $env:XCLI_STAGE_PATH
    if (-not $PathCandidate -and $envStagePath -and (Test-Path -LiteralPath $envStagePath -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $envStagePath).Path
    }

    $stageRoot = Join-Path $RepoRoot '.tmp-tests/xcli-stage'
    if (-not (Test-Path -LiteralPath $stageRoot -PathType Container)) {
        return $null
    }

    if (-not $Channel) {
        $Channel = $env:XCLI_STAGE_CHANNEL
    }

    if ($Channel) {
        $marker = Join-Path $stageRoot ("{0}-latest.txt" -f $Channel)
        if (Test-Path -LiteralPath $marker -PathType Leaf) {
            $path = (Get-Content -LiteralPath $marker -Raw).Trim()
            if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) {
                return (Resolve-Path -LiteralPath $path).Path
            }
        }
    }

    $latest = Get-ChildItem -LiteralPath $stageRoot -Recurse -Filter 'xcli-win-x64.zip' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latest) {
        return $latest.FullName
    }

    return $null
}

$StageChannel = if ($StageChannel) { $StageChannel } elseif ($env:XCLI_STAGE_CHANNEL) { $env:XCLI_STAGE_CHANNEL } else { 'local' }
$stageFullPath = Resolve-StagedArtifact -RepoRoot $RepoRoot -PathCandidate $StagePath -Channel $StageChannel
if (-not $stageFullPath) {
    throw '[xcli] No staged artifact found. Run the staging task first.'
}

if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
}

$extractDir = Join-Path $WorkDir 'extract'
if (Test-Path -LiteralPath $extractDir) {
    Remove-Item -LiteralPath $extractDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $extractDir | Out-Null

Write-Host ("[[xcli]] Extracting {0}…" -f $stageFullPath)
Expand-Archive -LiteralPath $stageFullPath -DestinationPath $extractDir -Force

$binary = Get-ChildItem -LiteralPath $extractDir -Filter 'XCli.exe' -Recurse | Select-Object -First 1
if (-not $binary) {
    throw "[xcli] Extracted archive does not contain XCli.exe."
}

Write-Host ("[[xcli]] Validating XCli binary at {0}" -f $binary.FullName)
$versionOutput = & $binary.FullName --version
if ($LASTEXITCODE -ne 0) {
    throw "[[xcli]] x-cli version command failed."
}
Write-Host ("[[xcli]] Binary version: {0}" -f $versionOutput)

$runnerProfile = Get-RunnerProfileSafe -Root $RepoRoot

$stageDir = Split-Path -Parent $stageFullPath
$stageInfoPath = Join-Path $stageDir 'stage-info.json'
if (-not (Test-Path -LiteralPath $stageInfoPath -PathType Leaf)) {
    throw "[xcli] stage-info.json not found at $stageInfoPath. Re-stage the artifact."
}

$stageInfo = Get-Content -LiteralPath $stageInfoPath -Raw | ConvertFrom-Json

$diagName = "xcli-diagnostics-{0}.json" -f (Split-Path -Leaf $stageDir)
$diagPath = Join-Path $stageDir $diagName
$diagnostics = [ordered]@{
    schema      = 'icon-editor/xcli-validation@v1'
    validatedAt = (Get-Date).ToString('o')
    stageDir    = $stageDir
    channel     = $StageChannel
    artifact    = $stageFullPath
    version     = $versionOutput
    runnerProfile = $runnerProfile
    telemetry   = [ordered]@{
        status  = 'skipped'
        summary = $null
    }
    labviewSmoke = @()
}

if ($RunLabVIEWSmoke) {
    Write-Warning "[[xcli]] LabVIEW smoke validation is not yet implemented in this script."
}

$diagnostics | ConvertTo-Json -Depth 6 | Out-File -FilePath $diagPath -Encoding UTF8
Write-Host ("[[xcli]] Validation diagnostics written to {0}" -f $diagPath)

$stageInfo.statuses.validated = [ordered]@{
    status      = 'passed'
    validatedAt = (Get-Date).ToString('o')
    diagnostics = $diagPath
    runnerProfile = $runnerProfile
}
$stageInfo | ConvertTo-Json -Depth 8 | Out-File -FilePath $stageInfoPath -Encoding UTF8

[pscustomobject]@{
    StagePath     = $stageFullPath
    StageDir      = $stageDir
    Diagnostics   = $diagPath
    RunnerProfile = $runnerProfile
}

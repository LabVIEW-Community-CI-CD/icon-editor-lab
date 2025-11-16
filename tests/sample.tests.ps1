$root = $env:WORKSPACE_ROOT
if (-not $root) { $root = '/mnt/data/repo_local' }
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    $scriptDir = Split-Path -Parent $PSCommandPath
    $probe = $scriptDir
    while ($probe -and (Split-Path -Leaf $probe) -ne 'tests') {
        $next = Split-Path -Parent $probe
        if (-not $next -or $next -eq $probe) { break }
        $probe = $next
    }
    if ($probe -and (Split-Path -Leaf $probe) -eq 'tests') {
        $root = Split-Path -Parent $probe
    }
    else {
        $root = $scriptDir
    }
}
$repoRoot = (Resolve-Path -LiteralPath $root).Path
$tmp = Join-Path $repoRoot '.tmp-tests'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
Describe 'sample' {
  It 'passes' {
    1 | Should -Be 1
  }
}

Describe 'Critical scripts' {
  BeforeAll {
    $script:CriticalRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:CriticalTmpRoot  = Join-Path $script:CriticalRepoRoot '.tmp-tests'
    New-Item -ItemType Directory -Force -Path $script:CriticalTmpRoot | Out-Null
  }

  It 'Check-DocsLinks validates a small doc tree and helper functions' {
    $scriptPath = Join-Path $script:CriticalRepoRoot 'src/tools/Check-DocsLinks.ps1'
    $workRoot = Join-Path $script:CriticalTmpRoot ("docs-links-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $workRoot 'target.md') -Value '# target' -Encoding UTF8
    '[ok](./target.md)' | Set-Content -LiteralPath (Join-Path $workRoot 'doc.md') -Encoding UTF8
    $jsonPath = Join-Path $workRoot 'summary.json'
    . $scriptPath -Path $workRoot -Quiet -HttpTimeoutSec 1 -OutputJson $jsonPath
    Invoke-WithTimeout -ScriptBlock { 'done' } -TimeoutSec 5 | Should -Be 'done'
    $allowList = Join-Path $workRoot 'allow.txt'
    'missing.md' | Set-Content -LiteralPath $allowList -Encoding UTF8
    'bad [link](missing.md)' | Set-Content -LiteralPath (Join-Path $workRoot 'allowed.md') -Encoding UTF8
    'ignored [link](missing-two.md)' | Set-Content -LiteralPath (Join-Path $workRoot 'ignored.md') -Encoding UTF8
    $oldSummary = $env:GITHUB_STEP_SUMMARY
    $env:GITHUB_STEP_SUMMARY = Join-Path $workRoot 'summary.txt'
    try {
      . $scriptPath -Path $workRoot -Quiet -AllowListPath $allowList -Ignore @('*/ignored.md') -HttpTimeoutSec '4'
    }
    finally {
      $env:GITHUB_STEP_SUMMARY = $oldSummary
    }
    Match-Any -value 'foo/bar' -patterns @('*/bar') | Should -BeTrue
    Write-Info 'docs links check' | Out-Null
  }

  It 'Check-WorkflowDrift completes when python/git are stubbed' {
    $scriptPath = Join-Path $script:CriticalRepoRoot 'src/tools/Check-WorkflowDrift.ps1'
    $stubDir = Join-Path $script:CriticalTmpRoot ("wf-stubs-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $stubDir | Out-Null
    $pythonStub = @"
#!/usr/bin/env bash
exit 0
"@
    $gitStub = @"
#!/usr/bin/env bash
if [[ "$1" == "status" ]]; then
  echo " M .github/workflows/dummy.yml"
  exit 0
fi
exit 0
"@
    $pythonPath = Join-Path $stubDir 'python'
    $gitPath = Join-Path $stubDir 'git'
    $pythonStub | Set-Content -LiteralPath $pythonPath -Encoding UTF8
    $gitStub | Set-Content -LiteralPath $gitPath -Encoding UTF8
    chmod +x $pythonPath
    chmod +x $gitPath
    $originalPath = $env:PATH
    $env:PATH = ("{0}:{1}" -f $stubDir, $originalPath)
    try {
      . $scriptPath -Stage:$true -CommitMessage 'pester'
      . $scriptPath -AutoFix:$true -Stage:$true -CommitMessage 'auto'
      Process-Staging -ChangedFiles @('.github/workflows/dummy.yml')
      $env:PATH = ''
      . $scriptPath
    }
    finally {
      $env:PATH = $originalPath
    }
  }

  It 'Agent-Wait start/end roundtrip writes markers' {
    $scriptPath = Join-Path $script:CriticalRepoRoot 'src/tools/Agent-Wait.ps1'
    . $scriptPath
    $resultsDir = Join-Path $script:CriticalTmpRoot ("agent-results-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
    $marker = Start-AgentWait -Reason 'test' -ExpectedSeconds 1 -ResultsDir $resultsDir -Id 'unit'
    Test-Path $marker | Should -BeTrue
    Start-Sleep -Milliseconds 50
    $result = End-AgentWait -ResultsDir $resultsDir -Id 'unit'
    $result | Should -Not -BeNullOrEmpty
    $result.withinMargin | Should -BeTrue
  }

  It 'Invoke-ViCompareLabVIEWCli handles dry-run requests' {
    $scriptPath = Join-Path $script:CriticalRepoRoot 'local-ci/windows/scripts/Invoke-ViCompareLabVIEWCli.ps1'
    $viCompareDir = Join-Path $script:CriticalTmpRoot ("vi-compare-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $viCompareDir | Out-Null
    $requestsPath = Join-Path $viCompareDir 'requests.json'
    $payload = @{
      requests = @(
        @{
          pairId = 'pair-1'
          baseline = 'fixture/base.vi'
          candidate = 'fixture/head.vi'
        }
      )
    } | ConvertTo-Json -Depth 4
    $payload | Set-Content -LiteralPath $requestsPath -Encoding UTF8
    $harness = Join-Path $script:CriticalTmpRoot 'vi-harness.ps1'
    "param(); 'noop'" | Set-Content -LiteralPath $harness -Encoding UTF8
    $outputRoot = Join-Path $script:CriticalTmpRoot ("vi-output-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
    & $scriptPath -RepoRoot $script:CriticalRepoRoot -RequestsPath $requestsPath -OutputRoot $outputRoot -HarnessScript $harness -DryRun
    $pairsPayload = @{
      pairs = @(
        @{
          pair_id = 'pair-2'
          labels = @('extra')
          baseline = @{ path = 'fixture/base2.vi' }
          candidate = @{ path = 'fixture/head2.vi' }
        }
      )
    } | ConvertTo-Json -Depth 4
    $pairsPath = Join-Path $viCompareDir 'pairs.json'
    $pairsPayload | Set-Content -LiteralPath $pairsPath -Encoding UTF8
    & $scriptPath -RepoRoot $script:CriticalRepoRoot -RequestsPath $pairsPath -OutputRoot $outputRoot -HarnessScript $harness -DryRun
    Test-Path (Join-Path $outputRoot 'captures') | Should -BeTrue
  }

  It 'Validate-Paths module enforces safe paths' {
    $modulePath = Join-Path $script:CriticalRepoRoot 'tools/Validate-Paths.psm1'
    Import-Module $modulePath -Force | Out-Null
    $dir = Join-Path $script:CriticalTmpRoot ("paths-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $safeFile = Join-Path $dir 'file.txt'
    'ok' | Set-Content -LiteralPath $safeFile -Encoding UTF8
    Test-PathSafe -Path $safeFile -RequireAbsolute | Should -BeTrue
    { Validate-PathSafe -Path (Join-Path $dir '..' '..' '??') } | Should -Throw
  }

  It 'Validate-Config enforces JSON + schema' {
    $scriptPath = Join-Path $script:CriticalRepoRoot 'tools/Validate-Config.ps1'
    $dir = Join-Path $script:CriticalTmpRoot ("config-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $configPath = Join-Path $dir 'config.json'
    '{"name":"icon"}' | Set-Content -LiteralPath $configPath -Encoding UTF8
    $schemaPath = Join-Path $dir 'schema.json'
    '{ "type": "object", "properties": { "name": { "type": "string" } }, "required": ["name"] }' | Set-Content -LiteralPath $schemaPath -Encoding UTF8
    & $scriptPath -ConfigPath $configPath -SchemaPath $schemaPath
  }

  It 'Hash-Artifacts writes checksum manifest' {
    $scriptPath = Join-Path $script:CriticalRepoRoot 'tools/Hash-Artifacts.ps1'
    $dir = Join-Path $script:CriticalTmpRoot ("hashes-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    1..3 | ForEach-Object {
      "file$_" | Set-Content -LiteralPath (Join-Path $dir "sample$_.txt") -Encoding UTF8
    }
    & $scriptPath -Root $dir -Output 'checksums.sha256'
    Test-Path (Join-Path $dir 'checksums.sha256') | Should -BeTrue
  }

  It 'Export-SemverBundle copies required assets' {
    $scriptPath = Join-Path $script:CriticalRepoRoot 'tools/Export-SemverBundle.ps1'
    $dest = Join-Path $script:CriticalTmpRoot ("semver-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    & $scriptPath -Destination $dest -Zip:$false -IncludeWorkflow:$false
    Test-Path (Join-Path $dest 'docs/semver-guard-kit.md') | Should -BeTrue
    Test-Path (Join-Path $dest 'src/tools/priority/validate-semver.mjs') | Should -BeTrue
    $targetRepo = Join-Path $script:CriticalTmpRoot ("semver-target-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $targetRepo | Out-Null
    & $scriptPath -Destination $dest -Zip:$false -IncludeWorkflow:$true -TargetRepoRoot $targetRepo
    Test-Path (Join-Path $targetRepo '.github/workflows/semver-guard.yml') | Should -BeTrue
  }
}

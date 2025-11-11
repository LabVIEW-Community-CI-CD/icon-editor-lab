[CmdletBinding()]
param()
#Requires -Version 7.0

Describe 'ConsoleWatch helpers' -Tag 'Unit','Tools','ConsoleWatch' {
    BeforeAll {
        $here = $PSScriptRoot
        if (-not $here -and $PSCommandPath) { $here = Split-Path -Parent $PSCommandPath }
        if (-not $here -and $MyInvocation.MyCommand.Path) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
        if (-not $here) { throw 'Unable to determine test root for ConsoleWatch specs.' }
        $script:RepoRoot = (Resolve-Path (Join-Path $here '..\..\..')).Path
        $script:ModulePath = (Resolve-Path (Join-Path $script:RepoRoot 'src/tools/ConsoleWatch.psm1')).Path
        Import-Module -Name $script:ModulePath -Force
    }

    AfterAll {
        if (Get-Module -Name ConsoleWatch -ErrorAction SilentlyContinue) {
            Remove-Module ConsoleWatch -Force -ErrorAction SilentlyContinue
        }
    }

    AfterEach {
        InModuleScope ConsoleWatch {
            if ($script:ConsoleWatchState) {
                foreach ($key in @($script:ConsoleWatchState.Keys)) {
                    $script:ConsoleWatchState.Remove($key) | Out-Null
                }
            }
        }
    }

    Context 'Start-ConsoleWatch' {
        It 'registers CIM events and seeds ndjson when watcher succeeds' {
            $outDir = Join-Path $TestDrive 'event-mode'
            Mock -CommandName Register-CimIndicationEvent -ModuleName ConsoleWatch -MockWith {
                param(
                    [string]$ClassName,
                    [string]$SourceIdentifier,
                    [scriptblock]$Action,
                    [Parameter(ValueFromRemainingArguments=$true)][object[]]$Remaining
                )
                [pscustomobject]@{ SourceIdentifier = $SourceIdentifier }
            }
            $id = Start-ConsoleWatch -OutDir $outDir -Targets @('PwSh',' CMD ')
            Test-Path (Join-Path $outDir 'console-spawns.ndjson') | Should -BeTrue
            $state = InModuleScope ConsoleWatch { param($key) $script:ConsoleWatchState[$key] } -ArgumentList $id
            $state.Mode | Should -Be 'event'
            $state.Targets | Should -Be @('pwsh','cmd')
            Assert-MockCalled -ModuleName ConsoleWatch -CommandName Register-CimIndicationEvent -Times 1
        }

        It 'ensures snapshot summaries preserve pre-existing captures when no new events' {
            $id = Start-ConsoleWatch -OutDir (Join-Path $TestDrive 'watch-snapshot') -Targets @('pwsh')
            $state = InModuleScope ConsoleWatch { param($key) $script:ConsoleWatchState[$key] } -ArgumentList $id
            $state.Mode | Should -Not -BeNullOrEmpty
            $state.Targets | Should -Contain 'pwsh'
        }
    }

    Context 'Stop-ConsoleWatch' {
        It 'aggregates event-mode records into a summary' {
            $outDir = Join-Path $TestDrive 'event-summary'
            New-Item -ItemType Directory -Force -Path $outDir | Out-Null
            $records = @(
                @{ ts = '2025-11-11T00:00:00Z'; pid = 11; name = 'pwsh'; ppid = 1; parentName = 'cmd'; cmd = 'pwsh -NoLogo'; hasWindow = $true },
                @{ ts = '2025-11-11T00:00:01Z'; pid = 12; name = 'pwsh'; ppid = 1; parentName = 'cmd'; cmd = 'pwsh -File build.ps1'; hasWindow = $false },
                @{ ts = '2025-11-11T00:00:02Z'; pid = 21; name = 'cmd';  ppid = 0; parentName = $null; cmd = 'cmd.exe /c'; hasWindow = $true }
            )
            $recPath = Join-Path $outDir 'console-spawns.ndjson'
            $records | ForEach-Object { $_ | ConvertTo-Json -Compress } | Set-Content -LiteralPath $recPath -Encoding utf8
            $id = 'ConsoleWatch_test'
            InModuleScope ConsoleWatch {
                param($stateId,$dir,$path)
                $script:ConsoleWatchState[$stateId] = @{ Mode='event'; OutDir=$dir; Targets=@('pwsh','cmd'); Path=$path }
            } -ArgumentList $id,$outDir,$recPath
            Mock -CommandName Unregister-Event -ModuleName ConsoleWatch -MockWith {
                param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Ignore)
            }
            Mock -CommandName Remove-Event -ModuleName ConsoleWatch -MockWith {
                param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Ignore)
            }
            $summary = Stop-ConsoleWatch -Id $id -OutDir $outDir -Phase 'post'
            $summary.counts.pwsh | Should -Be 2
            $summary.counts.cmd | Should -Be 1
            ($summary.last | Measure-Object).Count | Should -Be 3
            Test-Path (Join-Path $outDir 'console-watch-summary.json') | Should -BeTrue
        }

        It 'detects new processes in snapshot mode' {
            $outDir = Join-Path $TestDrive 'snapshot-summary'
            New-Item -ItemType Directory -Force -Path $outDir | Out-Null
            $id = 'ConsoleWatch_snapshot'
            $pre = @([pscustomobject]@{ ProcessName='pwsh'; Id=111; StartTime=(Get-Date) })
            InModuleScope ConsoleWatch {
                param($stateId,$dir,$preItems)
                $script:ConsoleWatchState[$stateId] = @{ Mode='snapshot'; OutDir=$dir; Targets=@('pwsh'); Pre=$preItems }
            } -ArgumentList $id,$outDir,$pre
            Mock -CommandName Get-Process -ModuleName ConsoleWatch -MockWith {
                param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Ignore)
                @(
                    [pscustomobject]@{ ProcessName='pwsh'; Id=111; StartTime=(Get-Date).AddSeconds(-5) },
                    [pscustomobject]@{ ProcessName='pwsh'; Id=222; StartTime=(Get-Date) }
                )
            }
            $summary = Stop-ConsoleWatch -Id $id -OutDir $outDir -Phase 'post'
            $summary.counts.pwsh | Should -Be 1
            $summary.last[0].pid | Should -Be 222
        }
    }
}

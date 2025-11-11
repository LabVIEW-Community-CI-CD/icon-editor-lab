[CmdletBinding()]
param()
#Requires -Version 7.0

Describe 'LabVIEW PID tracker helpers' -Tag 'Unit','Tools','LabVIEWPidTracker' {
    BeforeAll {
        $modulePath = Resolve-Path (Join-Path $PSScriptRoot '..\..\..' 'src/tools/LabVIEWPidTracker.psm1')
        Import-Module -Name $modulePath -Force
    }

    AfterAll {
        if (Get-Module -Name LabVIEWPidTracker -ErrorAction SilentlyContinue) {
            Remove-Module LabVIEWPidTracker -Force
        }
    }

    Context 'Resolve-LabVIEWPidContext' {
        It 'returns null when context parameter is missing or null' {
            Resolve-LabVIEWPidContext | Should -BeNullOrEmpty
            Resolve-LabVIEWPidContext -Context $null | Should -BeNullOrEmpty
        }

        It 'orders hash tables and nested objects recursively' {
            $input = @{
                bravo = 2
                alpha = @{ delta = 4; charlie = 3 }
            }
            $result = Resolve-LabVIEWPidContext -Context $input -Confirm:$false
            ($result | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) | Should -Be @('alpha','bravo')
            ($result.alpha | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) | Should -Be @('charlie','delta')
            $result.alpha.charlie | Should -Be 3
            $result.bravo | Should -Be 2
        }
    }

    Context 'Tracker lifecycle' {
        BeforeEach {
            $script:labProcess = [pscustomobject]@{
                Id = 4242
                ProcessName = 'LabVIEW'
                StartTime = (Get-Date '2025-11-11T00:00:00Z')
            }
            $script:timestamp = Get-Date '2025-11-11T00:00:00Z'
            Mock -ModuleName LabVIEWPidTracker -CommandName Get-Date -MockWith { $script:timestamp }
            Mock -ModuleName LabVIEWPidTracker -CommandName Get-Process -ParameterFilter { $PSBoundParameters.ContainsKey('Name') -and $Name -eq 'LabVIEW' } -MockWith {
                return ,$script:labProcess
            }
            Mock -ModuleName LabVIEWPidTracker -CommandName Get-Process -ParameterFilter { $PSBoundParameters.ContainsKey('Id') } -MockWith {
                if ($Id -eq $script:labProcess.Id) { return $script:labProcess }
                throw [System.ComponentModel.Win32Exception]::new("Process $Id not found")
            }
        }

        It 'records initialize observation with active LabVIEW process' {
            $tracker = Join-Path $TestDrive 'pid-tracker' 'tracker.json'
            $result = Start-LabVIEWPidTracker -TrackerPath $tracker -Source 'tests'
            $result.Observation.action | Should -Be 'initialize'
            Test-Path $tracker | Should -BeTrue
            $record = Get-Content $tracker -Raw | ConvertFrom-Json -Depth 6
            $record.observations[-1].action | Should -Be 'initialize'
        }

        It 'finalizes tracker when tracked process is gone' {
            $tracker = Join-Path $TestDrive 'pid-finalize' 'tracker.json'
            $null = Start-LabVIEWPidTracker -TrackerPath $tracker -Source 'tests'
            Mock -ModuleName LabVIEWPidTracker -CommandName Get-Process -ParameterFilter { $PSBoundParameters.ContainsKey('Id') } -MockWith {
                throw [System.ComponentModel.Win32Exception]::new("process not running")
            } -Verifiable
            $result = Stop-LabVIEWPidTracker -TrackerPath $tracker -Source 'tests'
            $result.Observation.action | Should -Be 'finalize'
            $result.Observation.running | Should -BeFalse
            $result.Observation.note | Should -Be 'no-tracked-pid'
            $record = Get-Content $tracker -Raw | ConvertFrom-Json -Depth 6
            ($record.observations | Select-Object -Last 1).action | Should -Be 'finalize'
        }
    }
}

$here = Split-Path -Parent $PSCommandPath
$testsRoot = (Resolve-Path (Join-Path $here '..')).Path
$repoRoot = (Resolve-Path (Join-Path $testsRoot '..')).Path
$compareModulePath = Join-Path $repoRoot 'src/tools/CompareVI.Tools/CompareVI.Tools.psm1'
Import-Module $compareModulePath -Force
$labviewProviderManifest = Join-Path $repoRoot 'src/tools/providers/labviewcli/labviewcli.Provider.psd1'
Import-Module $labviewProviderManifest -Force

Describe 'CompareVI.Tools' {
    Context 'Get-CompareVIScriptPath' {
        It 'returns the full path to an existing script' {
            $path = InModuleScope CompareVI.Tools {
                Get-CompareVIScriptPath -Name 'Compare-VIHistory.ps1'
            }
            $path | Should -Match 'Compare-VIHistory.ps1$'
            Test-Path -LiteralPath $path | Should -BeTrue
        }

        It 'throws when the requested script does not exist' {
            { InModuleScope CompareVI.Tools { Get-CompareVIScriptPath -Name 'does-not-exist.ps1' } } | Should -Throw
        }
    }

    Context 'Invoke-CompareVIHistory' {
        It 'runs the underlying script and clears the COMPAREVI_SCRIPTS_ROOT variable' {
            $historyStub = Join-Path $TestDrive 'Compare-VIHistory.ps1'
            $recordPath = Join-Path $TestDrive 'history.json'
            $scriptTemplate = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TargetPath
)
$payload = [ordered]@{
    TargetPath = $TargetPath
    ScriptsRoot = [System.Environment]::GetEnvironmentVariable('COMPAREVI_SCRIPTS_ROOT')
}
$payload | ConvertTo-Json | Set-Content -LiteralPath '__OUTPUT__' -Encoding UTF8
'@
            $scriptContent = $scriptTemplate.Replace('__OUTPUT__', $recordPath)
            Set-Content -LiteralPath $historyStub -Encoding UTF8 -Value $scriptContent

            Mock -ModuleName CompareVI.Tools Get-CompareVIScriptPath { $historyStub }

            InModuleScope CompareVI.Tools {
                Invoke-CompareVIHistory -TargetPath 'vi/lib/Icon.vi'
            }

            $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
            $record.TargetPath | Should -Be 'vi/lib/Icon.vi'
            $record.ScriptsRoot | Should -Not -BeNullOrEmpty
            (Test-Path Env:COMPAREVI_SCRIPTS_ROOT) | Should -BeFalse
        }
    }
}

Describe 'labviewcli.Provider' {
    Context 'Convert-ToBoolString' {
        It 'maps true to the string literal "true"' {
            InModuleScope labviewcli.Provider {
                Convert-ToBoolString -Value $true | Should -Be 'true'
            }
        }

        It 'maps false to the string literal "false"' {
            InModuleScope labviewcli.Provider {
                Convert-ToBoolString -Value $false | Should -Be 'false'
            }
        }
    }

    Context 'Get-LabVIEWCliArgs' {
        It 'builds CreateComparisonReport arguments with optional flags' {
            Mock -ModuleName labviewcli.Provider Resolve-LabVIEWPathFromParams { 'C:\LabVIEW.exe' }

            $args = InModuleScope labviewcli.Provider {
                Get-LabVIEWCliArgs -Operation 'CreateComparisonReport' -Params @{
                    vi1         = 'A.vi'
                    vi2         = 'B.vi'
                    reportPath  = 'out/report.html'
                    reportType  = 'html'
                    flags       = @('-flag1','-flag2')
                }
            }

            $args | Should -Contain '-OperationName'
            $args | Should -Contain 'CreateComparisonReport'
            $args | Should -Contain '-VI1'
            $args | Should -Contain 'A.vi'
            $args | Should -Contain '-VI2'
            $args | Should -Contain 'B.vi'
            $args | Should -Contain '-ReportPath'
            $args | Should -Contain 'out/report.html'
            $args | Should -Contain '-ReportType'
            $args | Should -Contain 'html'
            $args | Should -Contain '-flag1'
            $args | Should -Contain '-flag2'
            $args | Should -Contain '-LabVIEWPath'
            $args | Should -Contain 'C:\LabVIEW.exe'
        }

        It 'builds RunVI arguments honoring boolean switches' {
            $args = InModuleScope labviewcli.Provider {
                Get-LabVIEWCliArgs -Operation 'RunVI' -Params @{
                    viPath       = 'Main.vi'
                    showFP       = $true
                    abortOnError = $false
                    arguments    = @('foo','bar')
                }
            }

            $args | Should -Be @('-OperationName','RunVI','-VIPath','Main.vi','-ShowFrontPanel','true','-AbortOnError','false','foo','bar')
        }
    }
}

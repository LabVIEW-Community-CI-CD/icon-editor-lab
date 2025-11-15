[CmdletBinding()]
param()
#Requires -Version 7.0

function Get-CurrentScriptDirectory {
    if ($PSBoundParameters.ContainsKey('PSScriptRoot') -and $PSScriptRoot) { return $PSScriptRoot }
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Path $PSCommandPath -Parent) }
    if ($MyInvocation.MyCommand.Path) { return (Split-Path -Path $MyInvocation.MyCommand.Path -Parent) }
    return (Get-Location).Path
}

$script:TestRoot = Get-CurrentScriptDirectory
$script:RepoRoot = (Resolve-Path (Join-Path $script:TestRoot '..\..\..')).Path
$script:SigningScriptPath = (Resolve-Path (Join-Path $script:RepoRoot 'tools/Invoke-ScriptSigningBatch.ps1')).Path

Describe 'Invoke-ScriptSigningBatch sampling and metrics' -Tag 'Unit','Tools','ScriptSigning' {
    BeforeAll {
        $script:OriginalLocation = Get-Location
        Set-Location $RepoRoot
    }

    AfterAll {
        if ($script:OriginalLocation) {
            Set-Location $script:OriginalLocation
        }
    }

    It 'signs only the configured batch size with First sampling and emits metrics' {
        $workspace = Join-Path $TestDrive 'workspace'
        New-Item -ItemType Directory -Path $workspace | Out-Null

        # Create 10 dummy scripts under TestDrive
        $unsignedRoot = Join-Path $workspace 'unsigned'
        New-Item -ItemType Directory -Path $unsignedRoot | Out-Null
        1..10 | ForEach-Object {
            $p = Join-Path $unsignedRoot ("script{0}.ps1" -f $_)
            "Write-Output 'Script $_'" | Set-Content -Path $p -Encoding utf8
        }

        # Generate an ephemeral code-signing cert in the current user store
        $cert = New-SelfSignedCertificate -Subject 'CN=Unit Test Code Signing' -Type CodeSigningCert -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddDays(7)
        $thumb = $cert.Thumbprint

        # Prepare a summary file in TestDrive to capture metrics
        $summaryPath = Join-Path $workspace 'summary.md'

        # Invoke the signing batch with sampling enabled
        . $SigningScriptPath -Root $unsignedRoot `
            -CertificateThumbprint $thumb `
            -MaxFiles 10 `
            -MaxFilesPerBatch 3 `
            -SamplingMode 'First' `
            -PerFileTimeoutSeconds 10 `
            -Mode 'fork' `
            -SkipAlreadySigned `
            -VerboseEvery 0 `
            -EmitMetrics `
            -SummaryPath $summaryPath

        # Validate that at most 3 files were signed and all are Valid
        $scripts = Get-ChildItem $unsignedRoot -Filter '*.ps1' -File
        $signed = @()
        foreach ($s in $scripts) {
            $sig = Get-AuthenticodeSignature -FilePath $s.FullName
            if ($sig.Status -eq 'Valid') {
                $signed += $s
            }
        }

        $signed.Count | Should -BeLessOrEqual 3
        $signed.Count | Should -BeGreaterThan 0

        # Summary should contain a metrics JSON blob with expected fields
        $summaryContent = Get-Content $summaryPath -Raw
        $summaryContent | Should -Match '\[fork\] metrics: \{.+\}'
        $jsonText = ($summaryContent -split '\[fork\] metrics:\s*',2)[1] -replace '^\- ',''
        $jsonText = $jsonText.Trim()

        # The JSON may be followed by a newline; attempt to parse the object
        $line = ($jsonText -split "`r?`n")[0]
        $metrics = $line | ConvertFrom-Json

        $metrics.mode | Should -Be 'fork'
        $metrics.maxFilesPerBatch | Should -Be 3
        $metrics.samplingMode | Should -Be 'First'
        $metrics.processed | Should -BeLessOrEqual 3
        $metrics.totalDiscovered | Should -Be 10
    }
}


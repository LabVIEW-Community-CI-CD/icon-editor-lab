Describe 'Hash-Artifacts.ps1' {
    Context 'Invocation' {
        It 'writes checksums for every file in the tree' {
            $here = Split-Path -Parent $PSCommandPath
            $testsRoot = (Resolve-Path (Join-Path $here '..')).Path
            $repoRoot = (Resolve-Path (Join-Path $testsRoot '..')).Path
            $hashArtifactsScript = (Resolve-Path (Join-Path $repoRoot 'tools/Hash-Artifacts.ps1')).Path

            $root = Join-Path $TestDrive 'artifacts'
            New-Item -ItemType Directory -Path $root | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'a.txt') -Value 'a'
            New-Item -ItemType Directory -Path (Join-Path $root 'nested') | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'nested/b.txt') -Value 'b'

            $output = & $hashArtifactsScript -Root $root
            ($output -join [Environment]::NewLine) | Should -Match 'Wrote checksums'

            $checksumFile = Join-Path $root 'checksums.sha256'
            Test-Path -LiteralPath $checksumFile | Should -BeTrue
            $content = Get-Content -LiteralPath $checksumFile -Raw
            $content | Should -Match 'a\.txt'
            $content | Should -Match 'nested[/\\]b\.txt'
        }

        It 'throws when the root directory does not exist' {
            $here = Split-Path -Parent $PSCommandPath
            $testsRoot = (Resolve-Path (Join-Path $here '..')).Path
            $repoRoot = (Resolve-Path (Join-Path $testsRoot '..')).Path
            $hashArtifactsScript = (Resolve-Path (Join-Path $repoRoot 'tools/Hash-Artifacts.ps1')).Path

            { & $hashArtifactsScript -Root (Join-Path $TestDrive 'missing-root') } | Should -Throw
        }
    }
}

Describe 'Export-SemverBundle.ps1' {
    Context 'Bundle creation' {
        It 'creates a bundle directory, manifest, and optional zip' {
            $here = Split-Path -Parent $PSCommandPath
            $testsRoot = (Resolve-Path (Join-Path $here '..')).Path
            $repoRoot = (Resolve-Path (Join-Path $testsRoot '..')).Path
            $exportBundleScript = (Resolve-Path (Join-Path $repoRoot 'tools/Export-SemverBundle.ps1')).Path

            $destination = Join-Path $TestDrive 'bundle-out'
            & $exportBundleScript -Destination $destination -Zip -IncludeWorkflow | Out-Null

            Test-Path -LiteralPath $destination | Should -BeTrue
            Test-Path -LiteralPath "$destination.zip" | Should -BeTrue
            $manifest = Get-Content -LiteralPath (Join-Path $destination 'bundle.json') -Raw | ConvertFrom-Json
            ($manifest.files.relativePath) | Should -Contain 'docs/semver-guard-kit.md'
        }

        It 'copies bundle contents into a target repo when requested' {
            $here = Split-Path -Parent $PSCommandPath
            $testsRoot = (Resolve-Path (Join-Path $here '..')).Path
            $repoRoot = (Resolve-Path (Join-Path $testsRoot '..')).Path
            $exportBundleScript = (Resolve-Path (Join-Path $repoRoot 'tools/Export-SemverBundle.ps1')).Path

            $destination = Join-Path $TestDrive 'bundle-mirror'
            $targetRepo = Join-Path $TestDrive 'adopter'
            & $exportBundleScript -Destination $destination -TargetRepoRoot $targetRepo | Out-Null

            Test-Path -LiteralPath (Join-Path $targetRepo 'src/tools/priority/validate-semver.mjs') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $targetRepo 'docs/semver-guard-kit.md') | Should -BeTrue
        }
    }
}

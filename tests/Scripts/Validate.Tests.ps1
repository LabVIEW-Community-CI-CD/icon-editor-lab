Describe 'Validate-Paths.ps1' {
    Context 'Test-PathSafe' {
        It 'returns true for an absolute path that exists' {
            $here = Split-Path -Parent $PSCommandPath
            $testsRoot = (Resolve-Path (Join-Path $here '..')).Path
            $repoRoot = (Resolve-Path (Join-Path $testsRoot '..')).Path
            $modulePath = (Resolve-Path (Join-Path $repoRoot 'tools/Validate-Paths.psm1')).Path
            Import-Module $modulePath -Force

            $filePath = Join-Path $TestDrive 'valid.txt'
            'ok' | Set-Content -LiteralPath $filePath

            InModuleScope Validate-Paths {
                Test-PathSafe -Path $args[0] -RequireAbsolute | Should -BeTrue
            } -ArgumentList $filePath
        }

        It 'returns false for traversal or unsafe characters' {
            $here = Split-Path -Parent $PSCommandPath
            $testsRoot = (Resolve-Path (Join-Path $here '..')).Path
            $repoRoot = (Resolve-Path (Join-Path $testsRoot '..')).Path
            $modulePath = (Resolve-Path (Join-Path $repoRoot 'tools/Validate-Paths.psm1')).Path
            Import-Module $modulePath -Force

            InModuleScope Validate-Paths {
                Test-PathSafe -Path '../etc/passwd' | Should -BeFalse
            }
        }
    }

    Context 'Validate-PathSafe' {
        It 'resolves and returns a valid path' {
            $here = Split-Path -Parent $PSCommandPath
            $testsRoot = (Resolve-Path (Join-Path $here '..')).Path
            $repoRoot = (Resolve-Path (Join-Path $testsRoot '..')).Path
            $modulePath = (Resolve-Path (Join-Path $repoRoot 'tools/Validate-Paths.psm1')).Path
            Import-Module $modulePath -Force

            $dirPath = Join-Path $TestDrive 'safe'
            New-Item -ItemType Directory -Path $dirPath | Out-Null

            InModuleScope Validate-Paths {
                $resolved = Validate-PathSafe -Path $args[0]
                $resolved | Should -Be ((Resolve-Path -LiteralPath $args[0]).Path)
            } -ArgumentList $dirPath
        }

        It 'throws for invalid paths' {
            $here = Split-Path -Parent $PSCommandPath
            $testsRoot = (Resolve-Path (Join-Path $here '..')).Path
            $repoRoot = (Resolve-Path (Join-Path $testsRoot '..')).Path
            $modulePath = (Resolve-Path (Join-Path $repoRoot 'tools/Validate-Paths.psm1')).Path
            Import-Module $modulePath -Force

            { InModuleScope Validate-Paths { Validate-PathSafe -Path '../etc' } } | Should -Throw
        }
    }
}

Describe 'Validate-Config.ps1' {
    Context 'Invocation' {
        It 'prints a success message for valid JSON content' {
            $here = Split-Path -Parent $PSCommandPath
            $testsRoot = (Resolve-Path (Join-Path $here '..')).Path
            $repoRoot = (Resolve-Path (Join-Path $testsRoot '..')).Path
            $validateConfigScript = (Resolve-Path (Join-Path $repoRoot 'tools/Validate-Config.ps1')).Path

            $configPath = Join-Path $TestDrive 'config.json'
            '{"name":"icon"}' | Set-Content -LiteralPath $configPath -Encoding UTF8
            $schemaPath = Join-Path $TestDrive 'missing-schema.json'

            $output = & $validateConfigScript -ConfigPath $configPath -SchemaPath $schemaPath
            $output[-1] | Should -Match ([Regex]::Escape((Resolve-Path -LiteralPath $configPath).Path))
        }

        It 'throws when the JSON content is invalid' {
            $here = Split-Path -Parent $PSCommandPath
            $testsRoot = (Resolve-Path (Join-Path $here '..')).Path
            $repoRoot = (Resolve-Path (Join-Path $testsRoot '..')).Path
            $validateConfigScript = (Resolve-Path (Join-Path $repoRoot 'tools/Validate-Config.ps1')).Path

            $configPath = Join-Path $TestDrive 'invalid.json'
            'not-json' | Set-Content -LiteralPath $configPath -Encoding UTF8
            $schemaPath = Join-Path $TestDrive 'missing-schema.json'

            { & $validateConfigScript -ConfigPath $configPath -SchemaPath $schemaPath } | Should -Throw
        }
    }
}

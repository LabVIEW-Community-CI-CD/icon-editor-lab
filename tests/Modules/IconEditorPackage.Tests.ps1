$here = Split-Path -Parent $PSCommandPath
$testsRoot = (Resolve-Path (Join-Path $here '..')).Path
$repoRoot = (Resolve-Path (Join-Path $testsRoot '..')).Path
$modulePath = Join-Path $repoRoot 'src/tools/icon-editor/IconEditorPackage.psm1'
Import-Module $modulePath -Force

Describe 'IconEditorPackage' {
    Context 'Get-IconEditorPackageName' {
        It 'returns the trimmed package name from a VIPB file' {
            $vipbPath = Join-Path $TestDrive 'package.vipb'
            @'
<VI_Package_Builder_Settings>
  <Library_General_Settings>
    <Package_File_Name>IconPkg </Package_File_Name>
  </Library_General_Settings>
</VI_Package_Builder_Settings>
'@ | Set-Content -LiteralPath $vipbPath -Encoding UTF8

            InModuleScope IconEditorPackage {
                Get-IconEditorPackageName -VipbPath $args[0] | Should -Be 'IconPkg'
            } -ArgumentList $vipbPath
        }

        It 'throws when the Package_File_Name node is missing' {
            $vipbPath = Join-Path $TestDrive 'missing.vipb'
            '<VI_Package_Builder_Settings />' | Set-Content -LiteralPath $vipbPath -Encoding UTF8

            { InModuleScope IconEditorPackage { Get-IconEditorPackageName -VipbPath $args[0] } -ArgumentList $vipbPath } | Should -Throw
        }
    }

    Context 'Get-IconEditorPackagePath' {
        BeforeEach {
            $script:workspaceRoot = Join-Path $TestDrive ([guid]::NewGuid())
            New-Item -ItemType Directory -Path $script:workspaceRoot | Out-Null
            $script:vipbPath = Join-Path $script:workspaceRoot 'IconEditor.vipb'
            @'
<VI_Package_Builder_Settings>
  <Library_General_Settings>
    <Package_File_Name>IconPkg</Package_File_Name>
  </Library_General_Settings>
</VI_Package_Builder_Settings>
'@ | Set-Content -LiteralPath $script:vipbPath -Encoding UTF8
        }

        It 'builds the package path under the provided workspace root when output is relative' {
            $result = InModuleScope IconEditorPackage {
                Get-IconEditorPackagePath -VipbPath $args[0] -Major 1 -Minor 2 -Patch 3 -Build 4 -WorkspaceRoot $args[1] -OutputDirectory 'out/vip'
            } -ArgumentList $script:vipbPath, $script:workspaceRoot

            $expectedDir = [System.IO.Path]::GetFullPath((Join-Path $script:workspaceRoot 'out/vip'))
            $expectedPath = Join-Path $expectedDir 'IconPkg-1.2.3.4.vip'
            $result | Should -Be $expectedPath
        }

        It 'uses the current location when no workspace root is provided and honors absolute outputs' {
            $absoluteOutput = Join-Path $TestDrive 'artifacts'
            New-Item -ItemType Directory -Path $absoluteOutput | Out-Null
            $fallbackWorkspace = Join-Path $TestDrive 'fallback'
            New-Item -ItemType Directory -Path $fallbackWorkspace | Out-Null

            Mock -ModuleName IconEditorPackage Get-Location { [pscustomobject]@{ Path = $fallbackWorkspace } }

            $result = InModuleScope IconEditorPackage {
                Get-IconEditorPackagePath -VipbPath $args[0] -Major 2 -Minor 0 -Patch 0 -Build 1 -OutputDirectory $args[1]
            } -ArgumentList $script:vipbPath, $absoluteOutput

            $expectedPath = Join-Path $absoluteOutput 'IconPkg-2.0.0.1.vip'
            $result | Should -Be $expectedPath
        }
    }
}

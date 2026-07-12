#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbatoolsSupportPackage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Variables",
                "PassThru",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (TA-036): the package builds from local session/system state -
    # no SQL instance needed. A real run collects CIM facts and zips the dump.

    Context "Support package creation" {
        BeforeAll {
            $packagePath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $packagePath -ItemType Directory
        }

        AfterAll {
            Remove-Item -Path $packagePath -Recurse -ErrorAction SilentlyContinue
        }

        It "Emits nothing and creates nothing under -WhatIf" {
            $results = @(New-DbatoolsSupportPackage -Path $packagePath -WhatIf)
            $results.Count | Should -BeExactly 0
            @(Get-ChildItem -Path $packagePath).Count | Should -BeExactly 0
        }

        It "Creates the zip, removes the interim xml, and returns the zip FileInfo" {
            $results = @(New-DbatoolsSupportPackage -Path $packagePath)
            $results.Count | Should -BeExactly 1
            $results[0] | Should -BeOfType System.IO.FileInfo
            $results[0].Name | Should -Match "^dbatools_support_pack_.*\.zip$"
            $results[0].Length | Should -BeGreaterThan 0
            @(Get-ChildItem -Path $packagePath -Filter *.xml).Count | Should -BeExactly 0
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
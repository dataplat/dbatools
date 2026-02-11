#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaSpConfigure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Path",
                "FilePath",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $outputDir = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $outputDir -ItemType Directory
            $result = Export-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -Path $outputDir
        }

        AfterAll {
            Remove-Item -Path $outputDir -Recurse -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType System.IO.FileInfo
        }

        It "Returns a .sql file with sp_configure content" {
            $result.Extension | Should -Be ".sql"
            $content = Get-Content -Path $result.FullName -Raw
            $content | Should -Match "sp_configure"
        }
    }
}
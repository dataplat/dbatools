#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDirectory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Path",
                "SqlCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $testDirPath = "$($TestConfig.Temp)\dbatoolsci_newdir_$(Get-Random)"
        }

        AfterAll {
            Remove-Item -Path $testDirPath -Recurse -ErrorAction SilentlyContinue
        }

        It "Returns output with the expected properties" {
            $result = New-DbaDirectory -SqlInstance $TestConfig.InstanceSingle -Path $testDirPath
            $result | Should -Not -BeNullOrEmpty
            $result.Server | Should -Not -BeNullOrEmpty
            $result.Path | Should -Be $testDirPath
            $result.Created | Should -BeTrue
        }
    }
}
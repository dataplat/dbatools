#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaClientAlias",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $newAlias = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias -Verbose:$false
    }

    AfterAll {
        $newAlias | Remove-DbaClientAlias -ErrorAction SilentlyContinue
    }

    Context "gets the alias" {
        It "returns accurate information" {
            $results = Get-DbaClientAlias
            $results.AliasName -contains "dbatoolscialias" | Should -Be $true
        }
    }
}
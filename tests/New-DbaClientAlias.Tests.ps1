#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
        $ModuleName  = "dbatools",
    $CommandName = "New-DbaClientAlias",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "ServerName",
                "Alias",
                "Protocol",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When creating client alias" {
        AfterAll {
            # Cleanup - Remove any aliases that may have been created
            Get-DbaClientAlias -Alias "dbatoolscialias-new" -ErrorAction SilentlyContinue | Remove-DbaClientAlias -ErrorAction SilentlyContinue
        }

        It "Returns accurate information when creating alias" {
            $aliasName = "dbatoolscialias-new"
            $serverName = "sql2016"
            $results = New-DbaClientAlias -ServerName $serverName -Alias $aliasName -Verbose:$false
            $results.AliasName | Should -Be $aliasName, $aliasName

            # Clean up the created alias
            $results | Remove-DbaClientAlias
        }
    }
}
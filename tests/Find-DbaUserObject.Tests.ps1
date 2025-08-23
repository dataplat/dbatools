#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaUserObject",
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
                "Pattern",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name "dbatoolsci_userObject" -Owner "sa"

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_userObject"

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command finds User Objects for SA" {
        BeforeAll {
            $results = Find-DbaUserObject -SqlInstance $TestConfig.instance2 -Pattern "sa"
        }

        It "Should find a specific Database Owned by sa" {
            $results.Where( { $PSItem.name -eq "dbatoolsci_userobject" }).Type | Should -Be "Database"
        }

        It "Should find more than 10 objects Owned by sa" {
            $results.Count | Should -BeGreaterThan 10
        }
    }

    # TODO: What do we need to setup to find user objects? Skipping for now...
    Context -Skip "Command finds User Objects" {
        BeforeAll {
            $results = Find-DbaUserObject -SqlInstance $TestConfig.instance2
        }

        It "Should find results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
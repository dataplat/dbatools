#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbMemoryUsage",
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
                "Database",
                "ExcludeDatabase",
                "IncludeSystemDb",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $instance = Connect-DbaInstance -SqlInstance $TestConfig.instance2
    }

    Context "Functionality" {
        It "Returns data" {
            $result = Get-DbaDbMemoryUsage -SqlInstance $instance -IncludeSystemDb
            $result.Status.Count | Should -BeGreaterOrEqual 1
        }

        It "Accepts a list of databases" {
            $result = Get-DbaDbMemoryUsage -SqlInstance $instance -Database "ResourceDb" -IncludeSystemDb

            $uniqueDbs = $result.Database | Select-Object -Unique
            $uniqueDbs | Should -Be "ResourceDb"
        }

        It "Excludes databases" {
            $result = Get-DbaDbMemoryUsage -SqlInstance $instance -IncludeSystemDb -ExcludeDatabase "ResourceDb"

            $uniqueDbs = $result.Database | Select-Object -Unique
            $uniqueDbs | Should -Not -Contain "ResourceDb"
            $uniqueDbs | Should -Contain "master"
        }
    }
}
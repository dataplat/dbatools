#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaMaxDop",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaProcess -SqlInstance $TestConfig.instance2 -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $testDbName = "dbatoolsci_testMaxDop"
        $server.Query("CREATE DATABASE dbatoolsci_testMaxDop")
        $testDb = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $testDbName
        $setupSuccessful = $true
        if (-not $testDb) {
            $setupSuccessful = $false
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $testDbName | Remove-DbaDatabase -Confirm:$false

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    # Just not messin with this in appveyor
    Context "Command works on SQL Server 2016 or higher instances" {
        BeforeAll {
            if ($setupSuccessful) {
                $testResults = Test-DbaMaxDop -SqlInstance $TestConfig.instance2
            }
        }

        It "Should have correct properties" -Skip:(-not $setupSuccessful) {
            $expectedProps = "ComputerName", "InstanceName", "SqlInstance", "Database", "DatabaseMaxDop", "CurrentInstanceMaxDop", "RecommendedMaxDop", "Notes"
            foreach ($result in $testResults) {
                ($result.PSStandardMembers.DefaultDIsplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
            }
        }

        It "Should have only one result for database name of dbatoolsci_testMaxDop" -Skip:(-not $setupSuccessful) {
            @($testResults | Where-Object Database -eq $testDbName).Count | Should -Be 1
        }
    }
}
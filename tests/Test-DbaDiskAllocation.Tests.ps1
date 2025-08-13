#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaDiskAllocation",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "NoSqlCheck",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Command functionality" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            
            $splatStandard = @{
                ComputerName = $TestConfig.instance2
            }
            $standardResults = Test-DbaDiskAllocation @splatStandard
            
            $splatNoSql = @{
                ComputerName = $TestConfig.instance2
                NoSqlCheck   = $true
            }
            $noSqlResults = Test-DbaDiskAllocation @splatNoSql
            
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should return a result" {
            $standardResults | Should -Not -Be $null
        }

        It "Should return a result not using sql" {
            $noSqlResults | Should -Not -Be $null
        }
    }
}

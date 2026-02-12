#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDump",
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

# Not sure what is up with appveyor but it does not support this at all
if (-not $env:appveyor) {
    Describe $CommandName -Tag IntegrationTests {
        Context "Testing if memory dump is present" {
            It "finds least one dump" {
                $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

                $splatConnect = @{
                    SqlInstance = $TestConfig.InstanceSingle
                }
                $server = Connect-DbaInstance @splatConnect
                $server.Query("DBCC STACKDUMP")
                $server.Query("DBCC STACKDUMP")

                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

                $results = Get-DbaDump -SqlInstance $TestConfig.InstanceSingle
                $results.Count | Should -BeGreaterOrEqual 1
            }
        }

        Context "Output validation" {
            BeforeAll {
                $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
                $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
                $server.Query("DBCC STACKDUMP")
                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
                $result = Get-DbaDump -SqlInstance $TestConfig.InstanceSingle
            }

            It "Returns output of the documented type" {
                $result | Should -Not -BeNullOrEmpty
                $result[0] | Should -BeOfType PSCustomObject
            }

            It "Has the expected properties" {
                $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "FileName", "CreationTime", "Size")
                foreach ($prop in $expectedProps) {
                    $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
                }
            }
        }
    }
}
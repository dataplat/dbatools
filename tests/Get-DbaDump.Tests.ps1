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

        Context "Output Validation" {
            BeforeAll {
                $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

                $splatConnect = @{
                    SqlInstance = $TestConfig.InstanceSingle
                }
                $server = Connect-DbaInstance @splatConnect
                $server.Query("DBCC STACKDUMP")

                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

                $result = Get-DbaDump -SqlInstance $TestConfig.InstanceSingle -EnableException
            }

            It "Returns PSCustomObject" {
                $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
            }

            It "Has the expected default display properties" {
                $expectedProps = @(
                    "ComputerName",
                    "InstanceName",
                    "SqlInstance",
                    "FileName",
                    "CreationTime",
                    "Size"
                )
                $actualProps = $result[0].PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
                }
            }
        }
    }
}
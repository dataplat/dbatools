#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaMaxMemory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        Context "Validate functionality" {
            It "Server SqlInstance reported correctly" {
                Mock Connect-DbaInstance {
                    return @{
                        DomainInstanceName = "ABC"
                    }
                }

                (Get-DbaMaxMemory -SqlInstance "ABC").SqlInstance | Should -Be "ABC"
            }

            It "Server under-report by 1 the memory installed on the host" {
                Mock Connect-DbaInstance {
                    return @{
                        PhysicalMemory = 1023
                    }
                }

                (Get-DbaMaxMemory -SqlInstance "ABC").Total | Should -Be 1024
            }

            It "Server reports correctly the memory installed on the host" {
                Mock Connect-DbaInstance {
                    return @{
                        PhysicalMemory = 1024
                    }
                }

                (Get-DbaMaxMemory -SqlInstance "ABC").Total | Should -Be 1024
            }

            It "Memory allocated to SQL Server instance reported" {
                Mock Connect-DbaInstance {
                    return @{
                        Configuration = @{
                            MaxServerMemory = @{
                                ConfigValue = 2147483647
                            }
                        }
                    }
                }

                (Get-DbaMaxMemory -SqlInstance "ABC").MaxValue | Should -Be 2147483647
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
    }

    AfterAll {
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Connects to multiple instances" {
        It "Returns multiple objects" {
            $results = Get-DbaMaxMemory -SqlInstance $TestConfig.Instance1, $TestConfig.Instance2
            $results.Count | Should -BeGreaterThan 1 # and ultimately not throw an exception
        }

        It "Returns the right amount of" {
            $null = Set-DbaMaxMemory -SqlInstance $TestConfig.Instance1, $TestConfig.Instance2 -Max 1024
            $results = Get-DbaMaxMemory -SqlInstance $TestConfig.Instance1
            $results.MaxValue | Should -Be 1024
        }
    }
}
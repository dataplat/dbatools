#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaMaxMemory",
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

Describe $CommandName -Tag UnitTests {
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

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
    }

    AfterAll {
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Connects to multiple instances" {
        It "Returns multiple objects" {
            # Suppressing warning on Azure: [Test-DbaMaxMemory] The memory calculation may be inaccurate as the following SQL components have also been detected: SSIS,SSAS
            $results = Get-DbaMaxMemory -SqlInstance $TestConfig.Instance1, $TestConfig.Instance2 -WarningAction SilentlyContinue
            $results.Count | Should -BeGreaterThan 1 # and ultimately not throw an exception
        }

        It "Returns the right amount of" {
            # Suppressing warning on Azure: [Test-DbaMaxMemory] The memory calculation may be inaccurate as the following SQL components have also been detected: SSIS,SSAS
            $null = Set-DbaMaxMemory -SqlInstance $TestConfig.Instance1, $TestConfig.Instance2 -Max 1024 -WarningAction SilentlyContinue
            $results = Get-DbaMaxMemory -SqlInstance $TestConfig.Instance1
            $results.MaxValue | Should -Be 1024
        }
    }
}
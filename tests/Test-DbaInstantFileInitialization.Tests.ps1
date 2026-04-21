#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Test-DbaInstantFileInitialization",
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

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        Context "IFI best practice detection" {
            BeforeAll {
                $script:mockServices = @()
                $script:mockPrivileges = @()

                function Write-Message { }
                function Select-DefaultView {
                    param(
                        [Parameter(ValueFromPipeline)]
                        $InputObject,
                        [Parameter(ValueFromRemainingArguments)]
                        $RemainingArguments
                    )

                    process {
                        $InputObject
                    }
                }
                function Stop-Function {
                    param(
                        $Message,
                        $ErrorRecord,
                        $Target,
                        [switch]$Continue
                    )

                    throw "$Message :: $($ErrorRecord.Exception.Message)"
                }
                function Get-DbaService {
                    param(
                        $ComputerName,
                        $Credential,
                        $Type,
                        [switch]$EnableException
                    )

                    $script:mockServices
                }
                function Get-DbaPrivilege {
                    param(
                        $ComputerName,
                        $Credential,
                        [switch]$EnableException
                    )

                    $script:mockPrivileges
                }
            }

            It "Treats a matching virtual service StartName as best practice" {
                $script:mockServices = [PSCustomObject]@{
                    ComputerName = "sql1"
                    InstanceName = "MSSQLSERVER"
                    ServiceName  = "MSSQLSERVER"
                    StartName    = "NT SERVICE\MSSQLSERVER"
                }

                $script:mockPrivileges = [PSCustomObject]@{
                    User                      = "NT SERVICE\MSSQLSERVER"
                    InstantFileInitialization = $true
                }

                $result = Test-DbaInstantFileInitialization -ComputerName "sql1"

                $result.ServiceNameIFI | Should -BeTrue
                $result.StartNameIFI | Should -BeTrue
                $result.IsEnabled | Should -BeTrue
                $result.IsBestPractice | Should -BeTrue
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets IFI status" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $computerName = Resolve-DbaComputerName -ComputerName $TestConfig.InstanceSingle -Property ComputerName
            $results = Test-DbaInstantFileInitialization -ComputerName $computerName
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Results have expected properties" {
            $results[0].ComputerName | Should -Not -BeNullOrEmpty
            $results[0].ServiceName | Should -Not -BeNullOrEmpty
            $results[0].IsEnabled | Should -BeOfType [bool]
            $results[0].IsBestPractice | Should -BeOfType [bool]
        }
    }
}
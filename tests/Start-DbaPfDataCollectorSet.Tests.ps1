#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Start-DbaPfDataCollectorSet",
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
                "CollectorSet",
                "InputObject",
                "NoWait",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Deterministic start flow" {
        InModuleScope dbatools {
            BeforeEach {
                Mock Invoke-Command2 { }
                Mock Get-DbaPfDataCollectorSet {
                    [PSCustomObject]@{
                        ComputerName           = "mockhost"
                        State                  = "Running"
                        Name                   = "Mock Collector Set"
                        DataCollectorSetObject = [PSCustomObject]@{}
                    }
                }
            }

            It "starts a stopped piped collector set and carries NoWait to PLA" {
                $inputSet = [PSCustomObject]@{
                    ComputerName           = "mockhost"
                    State                  = "Stopped"
                    Name                   = "Mock Collector Set"
                    DataCollectorSetObject = [PSCustomObject]@{}
                }

                $result = $inputSet | Start-DbaPfDataCollectorSet -NoWait -Confirm:$false

                $result.ComputerName | Should -Be "mockhost"
                $result.Name | Should -Be "Mock Collector Set"
                Should -Invoke Invoke-Command2 -Times 1 -Exactly -ParameterFilter {
                    "$ComputerName" -eq "mockhost" -and
                    $ArgumentList.Count -eq 2 -and
                    $ArgumentList[0] -eq "Mock Collector Set" -and
                    $ArgumentList[1] -eq $false -and
                    $ErrorAction -eq "Stop"
                }
                Should -Invoke Get-DbaPfDataCollectorSet -Times 1 -Exactly -ParameterFilter {
                    "$ComputerName" -eq "mockhost" -and $CollectorSet -eq "Mock Collector Set"
                }
            }
        }
    }

    Context -Skip:(-not (Get-DbaPfDataCollectorSet -CollectorSet RTEvents)) "Verifying command works" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # We only run this on Azure as there is this collector set running:
            $null = Stop-DbaPfDataCollectorSet -CollectorSet RTEvents

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "returns a result with the right computername and name is not null" {
            $results = Start-DbaPfDataCollectorSet -CollectorSet RTEvents

            $WarnVar | Should -BeNullOrEmpty
            $results.ComputerName | Should -Be $env:COMPUTERNAME
            $results.Name | Should -Not -BeNullOrEmpty
        }
    }
}

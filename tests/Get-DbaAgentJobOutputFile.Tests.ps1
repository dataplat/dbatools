#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentJobOutputFile",
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
                "Job",
                "ExcludeJob",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Return values" {
        BeforeAll {
            Mock Connect-DbaInstance -MockWith {
                [object]@{
                    Name         = "SQLServerName"
                    ComputerName = "SQLServerName"
                    JobServer    = @{
                        Jobs = @(
                            @{
                                Name     = "Job1"
                                JobSteps = @(
                                    @{
                                        Id             = 1
                                        Name           = "Job1Step1"
                                        OutputFileName = "Job1Output1"
                                    },
                                    @{
                                        Id             = 2
                                        Name           = "Job1Step2"
                                        OutputFileName = "Job1Output2"
                                    }
                                )
                            },
                            @{
                                Name     = "Job2"
                                JobSteps = @(
                                    @{
                                        Id             = 1
                                        Name           = "Job2Step1"
                                        OutputFileName = "Job2Output1"
                                    },
                                    @{
                                        Id   = 2
                                        Name = "Job2Step2"
                                    }
                                )
                            },
                            @{
                                Name     = "Job3"
                                JobSteps = @(
                                    @{
                                        Id   = 1
                                        Name = "Job3Step1"
                                    },
                                    @{
                                        Id   = 2
                                        Name = "Job3Step2"
                                    }
                                )
                            }
                        )
                    }
                } #object
            } #mock Connect-DbaInstance
        }

        It "Gets only steps with output files" {
            $results = @(Get-DbaAgentJobOutputFile -SqlInstance "SQLServerName")
            $results.Count | Should -BeExactly 3
            $results.Job | Should -Match "Job[12]"
            $results.JobStep | Should -Match "Job[12]Step[12]"
            $results.OutputFileName | Should -Match "Job[12]Output[12]"
            $results.RemoteOutputFileName | Should -Match "\\\\SQLServerName\\Job[12]Output[12]"
        }

        It "Honors the Job parameter" {
            $results = @(Get-DbaAgentJobOutputFile -SqlInstance "SQLServerName" -Job "Job1")
            $results.Job | Should -Match "Job1"
            $results.JobStep | Should -Match "Job1Step[12]"
            $results.OutputFileName | Should -Match "Job1Output[12]"
        }

        It "Honors the ExcludeJob parameter" {
            $results = @(Get-DbaAgentJobOutputFile -SqlInstance "SQLServerName" -ExcludeJob "Job1")
            $results.Count | Should -BeExactly 1
            $results.Job | Should -Match "Job2"
            $results.OutputFileName | Should -Be "Job2Output1"
            $results.StepId | Should -BeExactly 1
        }

        It "Does not return even with a specific job without outputfiles" {
            $results = @(Get-DbaAgentJobOutputFile -SqlInstance "SQLServerName" -Job "Job3")
            $results.Count | Should -BeExactly 0
        }
    }
}
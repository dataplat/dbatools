#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentJobOutputFile",
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
                "Job",
                "ExcludeJob",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $jobName = "dbatoolsci_joboutputfile_$(Get-Random)"
        $outputPath = "C:\temp\$jobName.log"
        $splatJob = @{
            SqlInstance = $TestConfig.InstanceSingle
            Job         = $jobName
        }
        $null = New-DbaAgentJob @splatJob
        $splatOutputStep = @{
            SqlInstance   = $TestConfig.InstanceSingle
            Job           = $jobName
            StepName      = "output"
            StepId        = 1
            Subsystem     = "TransactSql"
            Command       = "SELECT 1;"
            OutputFileName = $outputPath
        }
        $null = New-DbaAgentJobStep @splatOutputStep
        $splatSilentStep = @{
            SqlInstance = $TestConfig.InstanceSingle
            Job         = $jobName
            StepName    = "silent"
            StepId      = 2
            Subsystem   = "TransactSql"
            Command     = "SELECT 2;"
        }
        $null = New-DbaAgentJobStep @splatSilentStep

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "Returns only the live step with a configured output file" {
        $results = @(Get-DbaAgentJobOutputFile -SqlInstance $TestConfig.InstanceSingle -Job $jobName -EnableException)
        $results.Count | Should -BeExactly 1
        $results[0].Job | Should -BeExactly $jobName
        $results[0].JobStep | Should -BeExactly "output"
        $results[0].OutputFileName | Should -BeExactly $outputPath
        $results[0].StepId | Should -BeExactly 1
        $results[0].RemoteOutputFileName | Should -Match "^\\\\"
    }
}

Describe $CommandName -Tag UnitTests {
    Context "Return values" {
        BeforeAll {
            InModuleScope "dbatools" {
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
        }

        It "Gets only steps with output files" {
            InModuleScope "dbatools" {
                $Results = @()
                $Results += Get-DbaAgentJobOutputFile -SqlInstance "SQLServerName"
                $Results.Count | Should -BeExactly 3
                $Results.Job | Should -Match "Job[12]"
                $Results.JobStep | Should -Match "Job[12]Step[12]"
                $Results.OutputFileName | Should -Match "Job[12]Output[12]"
                $Results.RemoteOutputFileName | Should -Match "\\\\SQLServerName\\Job[12]Output[12]"
            }
        }

        It "Honors the Job parameter" {
            InModuleScope "dbatools" {
                $Results = @()
                $Results += Get-DbaAgentJobOutputFile -SqlInstance "SQLServerName" -Job "Job1"
                $Results.Job | Should -Match "Job1"
                $Results.JobStep | Should -Match "Job1Step[12]"
                $Results.OutputFileName | Should -Match "Job1Output[12]"
            }
        }

        It "Honors the ExcludeJob parameter" {
            InModuleScope "dbatools" {
                $Results = @()
                $Results += Get-DbaAgentJobOutputFile -SqlInstance "SQLServerName" -ExcludeJob "Job1"
                $Results.Count | Should -BeExactly 1
                $Results.Job | Should -Match "Job2"
                $Results.OutputFileName | Should -Be "Job2Output1"
                $Results.StepId | Should -BeExactly 1
            }
        }

        It "Does not return even with a specific job without outputfiles" {
            InModuleScope "dbatools" {
                $Results = @()
                $Results += Get-DbaAgentJobOutputFile -SqlInstance "SQLServerName" -Job "Job3"
                $Results.Count | Should -BeExactly 0
            }
        }
    }
}

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

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $jobName = "dbatoolsci_outputfile_$(Get-Random)"
        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName
        $splatJobStep = @{
            SqlInstance    = $TestConfig.InstanceSingle
            Job            = $jobName
            StepName       = "Step 1"
            Subsystem      = "TransactSql"
            Command        = "SELECT 1"
            OutputFileName = "dbatoolsci_output.txt"
        }
        $null = New-DbaAgentJobStep @splatJobStep

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Confirm:$false -ErrorAction SilentlyContinue
    }

    Context "When getting output files" {
        It "Should return output file info for the test job" {
            $results = Get-DbaAgentJobOutputFile -SqlInstance $TestConfig.InstanceSingle -Job $jobName -OutVariable "global:dbatoolsciOutput"
            $results | Should -Not -BeNullOrEmpty
            $results.Job | Should -Be $jobName
            $results.OutputFileName | Should -Be "dbatoolsci_output.txt"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Job",
                "JobStep",
                "OutputFileName",
                "RemoteOutputFileName",
                "StepId"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Job",
                "JobStep",
                "OutputFileName",
                "RemoteOutputFileName"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}
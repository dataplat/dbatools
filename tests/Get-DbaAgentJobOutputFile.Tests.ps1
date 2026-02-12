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
    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputJobName = "dbatoolsci_outfile_$(Get-Random)"
            $outputFilePath = "$($TestConfig.Temp)\dbatoolsci_output_$(Get-Random).txt"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $outputJobName
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $outputJobName -StepName "dbatoolsci_outstep1" -Subsystem TransactSql -Command "select 1" -OutputFileName $outputFilePath

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $result = @(Get-DbaAgentJobOutputFile -SqlInstance $TestConfig.InstanceSingle -Job $outputJobName)
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $outputJobName -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Returns output" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Returns output of type PSCustomObject" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Job", "JobStep", "OutputFileName", "RemoteOutputFileName")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Does not include StepId in default display" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Not -Contain "StepId" -Because "StepId is excluded from default display"
        }

        It "Has StepId available as a property" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.Properties["StepId"] | Should -Not -BeNullOrEmpty
        }
    }
}
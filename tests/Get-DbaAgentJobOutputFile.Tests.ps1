param($ModuleName = 'dbatools')

Describe "Get-DbaAgentJobOutputFile" {
    BeforeAll {
        $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgentJobOutputFile
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Job",
            "ExcludeJob",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Return values" {
        BeforeAll {
            Mock Connect-DbaInstance -ModuleName $ModuleName -MockWith {
                [PSCustomObject]@{
                    Name         = 'SQLServerName'
                    ComputerName = 'SQLServerName'
                    JobServer    = @{
                        Jobs = @(
                            @{
                                Name     = 'Job1'
                                JobSteps = @(
                                    @{
                                        Id             = 1
                                        Name           = 'Job1Step1'
                                        OutputFileName = 'Job1Output1'
                                    },
                                    @{
                                        Id             = 2
                                        Name           = 'Job1Step2'
                                        OutputFileName = 'Job1Output2'
                                    }
                                )
                            },
                            @{
                                Name     = 'Job2'
                                JobSteps = @(
                                    @{
                                        Id             = 1
                                        Name           = 'Job2Step1'
                                        OutputFileName = 'Job2Output1'
                                    },
                                    @{
                                        Id   = 2
                                        Name = 'Job2Step2'
                                    }
                                )
                            },
                            @{
                                Name     = 'Job3'
                                JobSteps = @(
                                    @{
                                        Id   = 1
                                        Name = 'Job3Step1'
                                    },
                                    @{
                                        Id   = 2
                                        Name = 'Job3Step2'
                                    }
                                )
                            }
                        )
                    }
                }
            }
        }

        It "Gets only steps with output files" {
            $Results = Get-DbaAgentJobOutputFile -SqlInstance 'SQLServerName'
            $Results.Count | Should -Be 3
            $Results.Job | Should -Match 'Job[12]'
            $Results.JobStep | Should -Match 'Job[12]Step[12]'
            $Results.OutputFileName | Should -Match 'Job[12]Output[12]'
            $Results.RemoteOutputFileName | Should -Match '\\\\SQLServerName\\Job[12]Output[12]'
        }

        It "Honors the Job parameter" {
            $Results = Get-DbaAgentJobOutputFile -SqlInstance 'SQLServerName' -Job 'Job1'
            $Results.Job | Should -Match 'Job1'
            $Results.JobStep | Should -Match 'Job1Step[12]'
            $Results.OutputFileName | Should -Match 'Job1Output[12]'
        }

        It "Honors the ExcludeJob parameter" {
            $Results = Get-DbaAgentJobOutputFile -SqlInstance 'SQLServerName' -ExcludeJob 'Job1'
            $Results.Count | Should -Be 1
            $Results.Job | Should -Match 'Job2'
            $Results.OutputFileName | Should -Be 'Job2Output1'
            $Results.StepId | Should -Be 1
        }

        It "Does not return even with a specific job without outputfiles" {
            $Results = Get-DbaAgentJobOutputFile -SqlInstance 'SQLServerName' -Job 'Job3'
            $Results.Count | Should -Be 0
        }
    }
}

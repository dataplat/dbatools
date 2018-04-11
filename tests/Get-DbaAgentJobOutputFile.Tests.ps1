$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 5
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaAgentJobOutputFile).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'ExcludeJob', 'EnableException'
        It "Contains our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Contains $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Unittests" -Tag 'UnitTests' {
    InModuleScope 'dbatools' {
        Context "Return values" {
            Mock Connect-SQLInstance -MockWith {
                [object]@{
                    Name      = 'SQLServerName'
                    NetName   = 'SQLServerName'
                    JobServer = @{
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
                } #object
            } #mock connect-sqlserver
            It "Gets only steps with output files" {
                $Results = @()
                $Results += Get-DbaAgentJobOutputFile -SqlInstance 'SQLServerName'
                $Results.Length | Should Be 3
                $Results.Job | Should Match 'Job[12]'
                $Results.JobStep | Should Match 'Job[12]Step[12]'
                $Results.OutputFileName | Should Match 'Job[12]Output[12]'
                $Results.RemoteOutputFileName | Should Match '\\\\SQLServerName\\Job[12]Output[12]'
            }
            It "Honors the Job parameter" {
                $Results = @()
                $Results += Get-DbaAgentJobOutputFile -SqlInstance 'SQLServerName' -Job 'Job1'
                $Results.Job | Should Match 'Job1'
                $Results.JobStep | Should Match 'Job1Step[12]'
                $Results.OutputFileName | Should Match 'Job1Output[12]'
            }
            It "Honors the ExcludeJob parameter" {
                $Results = @()
                $Results += Get-DbaAgentJobOutputFile -SqlInstance 'SQLServerName' -ExcludeJob 'Job1'
                $Results.Length | Should Be 1
                $Results.Job | Should Match 'Job2'
                $Results.OutputFileName | Should Be 'Job2Output1'
                $Results.StepId | Should Be 1
            }
            It "Does not return even with a specific job without outputfiles" {
                $Results = @()
                $Results += Get-DbaAgentJobOutputFile -SqlInstance 'SQLServerName' -Job 'Job3'
                $Results.Length | Should Be 0
            }
        }
    }
}


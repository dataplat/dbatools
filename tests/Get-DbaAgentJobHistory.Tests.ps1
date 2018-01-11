$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 10
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaAgentJobHistory).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'ExcludeJob', 'StartDate', 'EndDate', 'NoJobSteps', 'WithOutputFile', 'JobCollection', 'EnableException'
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
        Mock Connect-SQLInstance -MockWith {
            # Thanks @Fred
            $obj = [PSCustomObject]@{
                Name                 = 'BASEName'
                NetName              = 'BASENetName'
                InstanceName         = 'BASEInstanceName'
                DomainInstanceName   = 'BASEDomainInstanceName'
                InstallDataDirectory = 'BASEInstallDataDirectory'
                ErrorLogPath         = 'BASEErrorLog_{0}_{1}_{2}_Path' -f "'", '"', ']'
                ServiceName          = 'BASEServiceName'
                JobServer            = New-Object PSObject
                ConnectionContext    = New-Object PSObject
            }
            Add-Member -InputObject $obj.ConnectionContext -Name ConnectionString  -MemberType NoteProperty -Value 'put=an=equal=in=it'
            Add-Member -InputObject $obj.JobServer -Name EnumJobHistory -MemberType ScriptMethod -Value {
                param ($filter)
                return @(
                    @{
                        JobName     = 'Job1'
                        JobID       = [guid]'E7718A84-8B43-46D0-8F8D-4FC4464F9FC5'
                        StepID      = 0
                        StepName    = '(Job outcome)'
                        RunDate     = [DateTime]::Parse('2017-09-26T13:00:00')
                        RunDuration = 2
                        RunStatus   = 0
                    },
                    @{
                        JobName     = 'Job1'
                        JobID       = [guid]'E7718A84-8B43-46D0-8F8D-4FC4464F9FC5'
                        StepID      = 1
                        StepName    = 'Job1Step1'
                        RunDate     = [DateTime]::Parse('2017-09-26T13:00:00')
                        RunDuration = 1
                        RunStatus   = 0
                    },
                    @{
                        JobName     = 'Job1'
                        JobID       = [guid]'E7718A84-8B43-46D0-8F8D-4FC4464F9FC5'
                        StepID      = 2
                        StepName    = 'Job1Step2'
                        RunDate     = [DateTime]::Parse('2017-09-26T13:00:01')
                        RunDuration = 1
                        RunStatus   = 0
                    },
                    @{
                        JobName     = 'Job2'
                        JobID       = [guid]'9C9A6819-58CE-451A-8DD7-6D17593F0DFA'
                        StepID      = 0
                        StepName    = '(Job outcome)'
                        RunDate     = [DateTime]::Parse('2017-09-26T01:00:00')
                        RunDuration = 2
                        RunStatus   = 0
                    },
                    @{
                        JobName     = 'Job2'
                        JobID       = [guid]'9C9A6819-58CE-451A-8DD7-6D17593F0DFA'
                        StepID      = 1
                        StepName    = 'Job2Step1'
                        RunDate     = [DateTime]::Parse('2017-09-26T01:00:00')
                        RunDuration = 1
                        RunStatus   = 0
                    },
                    @{
                        JobName     = 'Job2'
                        JobID       = [guid]'9C9A6819-58CE-451A-8DD7-6D17593F0DFA'
                        StepID      = 2
                        StepName    = 'Job2Step2'
                        RunDate     = [DateTime]::Parse('2017-09-26T01:00:01')
                        RunDuration = 1
                        RunStatus   = 0
                    }
                )
            }
            $obj.PSObject.TypeNames.Clear()
            $obj.PSObject.TypeNames.Add("Microsoft.SqlServer.Management.Smo.Server")
            return $obj
        } #mock connect-sqlserver
        Context "Return values" {

            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = 'Job1'
                        StepId         = 1
                        OutputFileName = 'Job1Output1'
                    },
                    @{
                        Job            = 'Job1'
                        StepId         = 2
                        OutputFileName = 'Job1Output2'
                    },
                    @{
                        Job            = 'Job2'
                        StepId         = 2
                        OutputFileName = 'Job2Output1'
                    }
                )
            }
            It "Throws when NoJobSteps and WithOutputFile" {
                { Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -NoJobSteps -WithOutputFile -EnableException } | Should Throw
            }
            It "Returns full history by default" {
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName'
                $Results.Length | Should Be 6
            }
            It "Returns only runs with no steps with NoJobSteps" {
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -NoJobSteps
                $Results.Length | Should Be 2
            }
            It "Figures out plain outputfiles" {
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -WithOutputFile
                # no output for outcomes
                ($Results | Where-Object StepID -eq 0).Length | Should Be 2
                ($Results | Where-Object StepID -eq 0).OutputFileName -Join '' | Should Be ''
                # correct output for job1
                ($Results | Where-Object StepID -ne 0 | Where-Object JobName -eq 'Job1').OutputFileName | Should Match 'Job1Output[12]'
                # correct output for job2
                ($Results | Where-Object StepID -eq 2 | Where-Object JobName -eq 'Job2').OutputFileName | Should Match 'Job2Output1'
                ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job2').OutputFileName | Should Be ''
            }
        }
        Context "SQL Agent Tokens" {
            It "Handles INST" {
                Mock Get-DbaAgentJobOutputFile -MockWith {
                    @(
                        @{
                            Job            = 'Job1'
                            StepId         = 1
                            OutputFileName = '$(INST)__Job1Output1'
                        }
                    )
                }
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -WithOutputFile

                ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job1').OutputFileName | Should Be 'BASEServiceName__Job1Output1'

            }
            It "Handles MACH" {
                Mock Get-DbaAgentJobOutputFile -MockWith {
                    @(
                        @{
                            Job            = 'Job1'
                            StepId         = 1
                            OutputFileName = '$(MACH)__Job1Output1'
                        }
                    )
                }
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -WithOutputFile

                ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job1').OutputFileName | Should Be 'BASENetName__Job1Output1'

            }
            It "Handles SQLDIR" {
                Mock Get-DbaAgentJobOutputFile -MockWith {
                    @(
                        @{
                            Job            = 'Job1'
                            StepId         = 1
                            OutputFileName = '$(SQLDIR)__Job1Output1'
                        }
                    )
                }
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -WithOutputFile

                ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job1').OutputFileName | Should Be 'BASEInstallDataDirectory__Job1Output1'

            }
            It "Handles SQLLOGDIR" {
                Mock Get-DbaAgentJobOutputFile -MockWith {
                    @(
                        @{
                            Job            = 'Job1'
                            StepId         = 1
                            OutputFileName = '$(SQLLOGDIR)__Job1Output1'
                        }
                    )
                }
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -WithOutputFile

                ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job1').OutputFileName | Should Be 'BASEErrorLog_''_"_]_Path__Job1Output1'

            }
            It "Handles SRVR" {
                Mock Get-DbaAgentJobOutputFile -MockWith {
                    @(
                        @{
                            Job            = 'Job1'
                            StepId         = 1
                            OutputFileName = '$(SRVR)__Job1Output1'
                        }
                    )
                }
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -WithOutputFile

                ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job1').OutputFileName | Should Be 'BASEDomainInstanceName__Job1Output1'

            }

            It "Handles STEPID" {
                Mock Get-DbaAgentJobOutputFile -MockWith {
                    @(
                        @{
                            Job            = 'Job1'
                            StepId         = 1
                            OutputFileName = '$(STEPID)__Job1Output1'
                        }
                    )
                }
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -WithOutputFile
                ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job1').OutputFileName | Should Be '1__Job1Output1'

            }
            It "Handles JOBID" {
                Mock Get-DbaAgentJobOutputFile -MockWith {
                    @(
                        @{
                            Job            = 'Job1'
                            StepId         = 1
                            OutputFileName = '$(JOBID)__Job1Output1'
                        }
                    )
                }
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -WithOutputFile

                ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job1').OutputFileName | Should Be '0x848A71E7438BD0468F8D4FC4464F9FC5__Job1Output1'

            }


            It "Handles STRTDT" {
                Mock Get-DbaAgentJobOutputFile -MockWith {
                    @(
                        @{
                            Job            = 'Job1'
                            StepId         = 1
                            OutputFileName = '$(STRTDT)__Job1Output1'
                        }
                    )
                }
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -WithOutputFile
                ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job1').OutputFileName | Should Be '20170926__Job1Output1'
            }
            It "Handles STRTTM" {
                Mock Get-DbaAgentJobOutputFile -MockWith {
                    @(
                        @{
                            Job            = 'Job1'
                            StepId         = 1
                            OutputFileName = '$(STRTTM)__Job1Output1'
                        }
                    )
                }
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -WithOutputFile
                ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job1').OutputFileName | Should Be '130000__Job1Output1'
            }
            It "Handles DATE" {
                Mock Get-DbaAgentJobOutputFile -MockWith {
                    @(
                        @{
                            Job            = 'Job1'
                            StepId         = 1
                            OutputFileName = '$(DATE)__Job1Output1'
                        }
                    )
                }
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -WithOutputFile
                ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job1').OutputFileName | Should Be '20170926__Job1Output1'
            }

            It "Handles TIME" {
                Mock Get-DbaAgentJobOutputFile -MockWith {
                    @(
                        @{
                            Job            = 'Job1'
                            StepId         = 2
                            OutputFileName = '$(TIME)__Job1Output1'
                        }
                    )
                }
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -WithOutputFile
                ($Results | Where-Object StepID -eq 2 | Where-Object JobName -eq 'Job1').OutputFileName | Should Be '130001__Job1Output1'

            }
        }
        Context "SQL Agent escape sequences" {
            It "Handles ESCAPE_NONE" {
                Mock Get-DbaAgentJobOutputFile -MockWith {
                    @(
                        @{
                            Job            = 'Job1'
                            StepId         = 1
                            OutputFileName = '$(ESCAPE_NONE(SQLLOGDIR))__Job1Output1'
                        }
                    )
                }
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -WithOutputFile

                ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job1').OutputFileName | Should Be 'BASEErrorLog_''_"_]_Path__Job1Output1'

            }
            It "Handles ESCAPE_SQUOTE" {
                Mock Get-DbaAgentJobOutputFile -MockWith {
                    @(
                        @{
                            Job            = 'Job1'
                            StepId         = 1
                            OutputFileName = '$(ESCAPE_SQUOTE(SQLLOGDIR))__Job1Output1'
                        }
                    )
                }
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -WithOutputFile

                ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job1').OutputFileName | Should Be 'BASEErrorLog_''''_"_]_Path__Job1Output1'

            }
            It "Handles ESCAPE_DQUOTE" {
                Mock Get-DbaAgentJobOutputFile -MockWith {
                    @(
                        @{
                            Job            = 'Job1'
                            StepId         = 1
                            OutputFileName = '$(ESCAPE_DQUOTE(SQLLOGDIR))__Job1Output1'
                        }
                    )
                }
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -WithOutputFile

                ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job1').OutputFileName | Should Be 'BASEErrorLog_''_""_]_Path__Job1Output1'

            }
            It "Handles ESCAPE_RBRACKET" {
                Mock Get-DbaAgentJobOutputFile -MockWith {
                    @(
                        @{
                            Job            = 'Job1'
                            StepId         = 1
                            OutputFileName = '$(ESCAPE_RBRACKET(SQLLOGDIR))__Job1Output1'
                        }
                    )
                }
                $Results = @()
                $Results += Get-DbaAgentJobHistory -SqlInstance 'SQLServerName' -WithOutputFile

                ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job1').OutputFileName | Should Be 'BASEErrorLog_''_"_]]_Path__Job1Output1'

            }
        }
    }
}

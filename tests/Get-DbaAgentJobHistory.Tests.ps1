#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentJobHistory",
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
                "StartDate",
                "EndDate",
                "OutcomeType",
                "ExcludeJobSteps",
                "WithOutputFile",
                "JobCollection",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag UnitTests {
    BeforeAll {
        # Main mock for Connect-DbaInstance - moved to BeforeAll for proper scoping
        Mock Connect-DbaInstance -MockWith {
            # Thanks @Fred
            $obj = [PSCustomObject]@{
                Name                 = "BASEName"
                ComputerName         = "BASEComputerName"
                InstanceName         = "BASEInstanceName"
                DomainInstanceName   = "BASEDomainInstanceName"
                InstallDataDirectory = "BASEInstallDataDirectory"
                ErrorLogPath         = "BASEErrorLog_{0}_{1}_{2}_Path" -f "'", '"', "]"
                ServiceName          = "BASEServiceName"
                JobServer            = New-Object PSObject
                ConnectionContext    = New-Object PSObject
            }
            Add-Member -InputObject $obj.ConnectionContext -Name ConnectionString  -MemberType NoteProperty -Value "put=an=equal=in=it"
            Add-Member -InputObject $obj.JobServer -Name EnumJobHistory -MemberType ScriptMethod -Value {
                param ($filter)
                return @(
                    @{
                        JobName     = "Job1"
                        JobID       = [guid]"E7718A84-8B43-46D0-8F8D-4FC4464F9FC5"
                        StepID      = 0
                        StepName    = "(Job outcome)"
                        RunDate     = [DateTime]::Parse("2017-09-26T13:00:00")
                        RunDuration = 112
                        RunStatus   = 0
                    },
                    @{
                        JobName     = "Job1"
                        JobID       = [guid]"E7718A84-8B43-46D0-8F8D-4FC4464F9FC5"
                        StepID      = 1
                        StepName    = "Job1Step1"
                        RunDate     = [DateTime]::Parse("2017-09-26T13:00:00")
                        RunDuration = 1
                        RunStatus   = 0
                    },
                    @{
                        JobName     = "Job1"
                        JobID       = [guid]"E7718A84-8B43-46D0-8F8D-4FC4464F9FC5"
                        StepID      = 2
                        StepName    = "Job1Step2"
                        RunDate     = [DateTime]::Parse("2017-09-26T13:00:01")
                        RunDuration = 1
                        RunStatus   = 0
                    },
                    @{
                        JobName     = "Job2"
                        JobID       = [guid]"9C9A6819-58CE-451A-8DD7-6D17593F0DFA"
                        StepID      = 0
                        StepName    = "(Job outcome)"
                        RunDate     = [DateTime]::Parse("2017-09-26T01:00:00")
                        RunDuration = 2
                        RunStatus   = 0
                    },
                    @{
                        JobName     = "Job2"
                        JobID       = [guid]"9C9A6819-58CE-451A-8DD7-6D17593F0DFA"
                        StepID      = 1
                        StepName    = "Job2Step1"
                        RunDate     = [DateTime]::Parse("2017-09-26T01:00:00")
                        RunDuration = 1
                        RunStatus   = 0
                    },
                    @{
                        JobName     = "Job2"
                        JobID       = [guid]"9C9A6819-58CE-451A-8DD7-6D17593F0DFA"
                        StepID      = 2
                        StepName    = "Job2Step2"
                        RunDate     = [DateTime]::Parse("2017-09-26T01:00:01")
                        RunDuration = 1
                        RunStatus   = 0
                    }
                )
            }
            $obj.PSObject.TypeNames.Clear()
            $obj.PSObject.TypeNames.Add("Microsoft.SqlServer.Management.Smo.Server")
            return $obj
        }
    }

    Context "Return values" {
        BeforeAll {
            # Default mock for Get-DbaAgentJobOutputFile
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = "Job1"
                        StepId         = 1
                        OutputFileName = "Job1Output1"
                    },
                    @{
                        Job            = "Job1"
                        StepId         = 2
                        OutputFileName = "Job1Output2"
                    },
                    @{
                        Job            = "Job2"
                        StepId         = 2
                        OutputFileName = "Job2Output1"
                    }
                )
            }
        }

        It "Throws when ExcludeJobSteps and WithOutputFile" {
            { Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -ExcludeJobSteps -WithOutputFile -EnableException } | Should -Throw
        }

        It "Returns full history by default" {
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName")
            $Results.Count | Should -Be 6
        }

        It "Returns only runs with no steps with ExcludeJobSteps" {
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -ExcludeJobSteps)
            $Results.Count | Should -Be 2
        }

        It "Returns our own 'augmented' properties, too" {
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -ExcludeJobSteps)
            $Results[0].psobject.properties.Name | Should -Contain "StartDate"
            $Results[0].psobject.properties.Name | Should -Contain "EndDate"
            $Results[0].psobject.properties.Name | Should -Contain "Duration"
        }

        It "Returns 'augmented' properties that are correct" {
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -ExcludeJobSteps)
            $Results[0].StartDate | Should -Be $Results[0].RunDate
            $Results[0].RunDuration | Should -Be 112
            $Results[0].Duration.TotalSeconds | Should -Be 72
            $Results[0].EndDate | Should -Be ($Results[0].StartDate.AddSeconds($Results[0].Duration.TotalSeconds))
        }

        It "Figures out plain outputfiles" {
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -WithOutputFile)
            # no output for outcomes
            ($Results | Where-Object StepID -eq 0).Count | Should -Be 2
            ($Results | Where-Object StepID -eq 0).OutputFileName -Join "" | Should -Be ""
            # correct output for job1
            ($Results | Where-Object { $_.StepID -ne 0 -and $_.JobName -eq "Job1" }).OutputFileName | Should -Match "Job1Output[12]"
            # correct output for job2
            ($Results | Where-Object { $_.StepID -eq 2 -and $_.JobName -eq "Job2" }).OutputFileName | Should -Match "Job2Output1"
            ($Results | Where-Object { $_.StepID -eq 1 -and $_.JobName -eq "Job2" }).OutputFileName | Should -Be ""
        }
    }

    Context "SQL Agent Tokens" {
        It "Handles INST" {
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = "Job1"
                        StepId         = 1
                        OutputFileName = "`$(INST)__Job1Output1"
                    }
                )
            }
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -WithOutputFile)
            ($Results | Where-Object { $_.StepID -eq 1 -and $_.JobName -eq "Job1" }).OutputFileName | Should -Be "BASEServiceName__Job1Output1"
        }

        It "Handles MACH" {
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = "Job1"
                        StepId         = 1
                        OutputFileName = "`$(MACH)__Job1Output1"
                    }
                )
            }
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -WithOutputFile)
            ($Results | Where-Object { $_.StepID -eq 1 -and $_.JobName -eq "Job1" }).OutputFileName | Should -Be "BASEComputerName__Job1Output1"
        }

        It "Handles SQLDIR" {
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = "Job1"
                        StepId         = 1
                        OutputFileName = "`$(SQLDIR)__Job1Output1"
                    }
                )
            }
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -WithOutputFile)
            ($Results | Where-Object { $_.StepID -eq 1 -and $_.JobName -eq "Job1" }).OutputFileName | Should -Be "BASEInstallDataDirectory__Job1Output1"
        }

        It "Handles SQLLOGDIR" {
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = "Job1"
                        StepId         = 1
                        OutputFileName = "`$(SQLLOGDIR)__Job1Output1"
                    }
                )
            }
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -WithOutputFile)
            ($Results | Where-Object { $_.StepID -eq 1 -and $_.JobName -eq "Job1" }).OutputFileName | Should -Be "BASEErrorLog_'_`"_]_Path__Job1Output1"
        }

        It "Handles SRVR" {
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = "Job1"
                        StepId         = 1
                        OutputFileName = "`$(SRVR)__Job1Output1"
                    }
                )
            }
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -WithOutputFile)
            ($Results | Where-Object { $_.StepID -eq 1 -and $_.JobName -eq "Job1" }).OutputFileName | Should -Be "BASEDomainInstanceName__Job1Output1"
        }

        It "Handles STEPID" {
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = "Job1"
                        StepId         = 1
                        OutputFileName = "`$(STEPID)__Job1Output1"
                    }
                )
            }
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -WithOutputFile)
            ($Results | Where-Object { $_.StepID -eq 1 -and $_.JobName -eq "Job1" }).OutputFileName | Should -Be "1__Job1Output1"
        }

        It "Handles JOBID" {
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = "Job1"
                        StepId         = 1
                        OutputFileName = "`$(JOBID)__Job1Output1"
                    }
                )
            }
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -WithOutputFile)
            ($Results | Where-Object { $_.StepID -eq 1 -and $_.JobName -eq "Job1" }).OutputFileName | Should -Be "0x848A71E7438BD0468F8D4FC4464F9FC5__Job1Output1"
        }

        It "Handles STRTDT" {
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = "Job1"
                        StepId         = 1
                        OutputFileName = "`$(STRTDT)__Job1Output1"
                    }
                )
            }
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -WithOutputFile)
            ($Results | Where-Object { $_.StepID -eq 1 -and $_.JobName -eq "Job1" }).OutputFileName | Should -Be "20170926__Job1Output1"
        }

        It "Handles STRTTM" {
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = "Job1"
                        StepId         = 1
                        OutputFileName = "`$(STRTTM)__Job1Output1"
                    }
                )
            }
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -WithOutputFile)
            ($Results | Where-Object { $_.StepID -eq 1 -and $_.JobName -eq "Job1" }).OutputFileName | Should -Be "130000__Job1Output1"
        }

        It "Handles DATE" {
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = "Job1"
                        StepId         = 1
                        OutputFileName = "`$(DATE)__Job1Output1"
                    }
                )
            }
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -WithOutputFile)
            ($Results | Where-Object { $_.StepID -eq 1 -and $_.JobName -eq "Job1" }).OutputFileName | Should -Be "20170926__Job1Output1"
        }

        It "Handles TIME" {
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = "Job1"
                        StepId         = 2
                        OutputFileName = "`$(TIME)__Job1Output1"
                    }
                )
            }
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -WithOutputFile)
            ($Results | Where-Object { $_.StepID -eq 2 -and $_.JobName -eq "Job1" }).OutputFileName | Should -Be "130001__Job1Output1"
        }
    }

    Context "SQL Agent escape sequences" {
        It "Handles ESCAPE_NONE" {
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = "Job1"
                        StepId         = 1
                        OutputFileName = "`$(ESCAPE_NONE(SQLLOGDIR))__Job1Output1"
                    }
                )
            }
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -WithOutputFile)
            ($Results | Where-Object { $_.StepID -eq 1 -and $_.JobName -eq "Job1" }).OutputFileName | Should -Be "BASEErrorLog_'_`"_]_Path__Job1Output1"
        }

        It "Handles ESCAPE_SQUOTE" {
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = "Job1"
                        StepId         = 1
                        OutputFileName = "`$(ESCAPE_SQUOTE(SQLLOGDIR))__Job1Output1"
                    }
                )
            }
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -WithOutputFile)
            ($Results | Where-Object { $_.StepID -eq 1 -and $_.JobName -eq "Job1" }).OutputFileName | Should -Be "BASEErrorLog_''_`"_]_Path__Job1Output1"
        }

        It "Handles ESCAPE_DQUOTE" {
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = "Job1"
                        StepId         = 1
                        OutputFileName = "`$(ESCAPE_DQUOTE(SQLLOGDIR))__Job1Output1"
                    }
                )
            }
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -WithOutputFile)
            ($Results | Where-Object { $_.StepID -eq 1 -and $_.JobName -eq "Job1" }).OutputFileName | Should -Be "BASEErrorLog_'_`"`"_]_Path__Job1Output1"
        }

        It "Handles ESCAPE_RBRACKET" {
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = "Job1"
                        StepId         = 1
                        OutputFileName = "`$(ESCAPE_RBRACKET(SQLLOGDIR))__Job1Output1"
                    }
                )
            }
            $Results = @(Get-DbaAgentJobHistory -SqlInstance "SQLServerName" -WithOutputFile)
            ($Results | Where-Object { $_.StepID -eq 1 -and $_.JobName -eq "Job1" }).OutputFileName | Should -Be "BASEErrorLog_'_`"_]]_Path__Job1Output1"
        }
    }
}
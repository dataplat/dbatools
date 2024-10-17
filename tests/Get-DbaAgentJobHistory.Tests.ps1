param($ModuleName = 'dbatools')

Describe "Get-DbaAgentJobHistory Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Move setup code here
        $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command -Name $CommandName
        }
        It "Should have SqlInstance parameter" {
            $command | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $command | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Job parameter" {
            $command | Should -HaveParameter Job -Type Object[] -Not -Mandatory
        }
        It "Should have ExcludeJob parameter" {
            $command | Should -HaveParameter ExcludeJob -Type Object[] -Not -Mandatory
        }
        It "Should have StartDate parameter" {
            $command | Should -HaveParameter StartDate -Type DateTime -Not -Mandatory
        }
        It "Should have EndDate parameter" {
            $command | Should -HaveParameter EndDate -Type DateTime -Not -Mandatory
        }
        It "Should have OutcomeType parameter" {
            $command | Should -HaveParameter OutcomeType -Type CompletionResult -Not -Mandatory
        }
        It "Should have ExcludeJobSteps parameter" {
            $command | Should -HaveParameter ExcludeJobSteps -Type SwitchParameter -Not -Mandatory
        }
        It "Should have WithOutputFile parameter" {
            $command | Should -HaveParameter WithOutputFile -Type SwitchParameter -Not -Mandatory
        }
        It "Should have JobCollection parameter" {
            $command | Should -HaveParameter JobCollection -Type Job -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $command | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }
}

Describe "Get-DbaAgentJobHistory Integration Tests" -Tag 'IntegrationTests' {
    BeforeAll {
        $PSDefaultParameterValues["*:SqlInstance"] = "SQLServerName"
        $PSDefaultParameterValues["*:ModuleName"] = $ModuleName

        Mock Connect-DbaInstance -MockWith {
            $obj = [PSCustomObject]@{
                Name                 = 'BASEName'
                ComputerName         = 'BASEComputerName'
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
                        RunDuration = 112
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
        }

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
    }

    Context "Return values" {
        It "Throws when ExcludeJobSteps and WithOutputFile" {
            { Get-DbaAgentJobHistory -ExcludeJobSteps -WithOutputFile -EnableException } | Should -Throw
        }

        It "Returns full history by default" {
            $Results = Get-DbaAgentJobHistory
            $Results.Count | Should -Be 6
        }

        It "Returns only runs with no steps with ExcludeJobSteps" {
            $Results = Get-DbaAgentJobHistory -ExcludeJobSteps
            $Results.Count | Should -Be 2
        }

        It 'Returns our own "augmented" properties, too' {
            $Results = Get-DbaAgentJobHistory -ExcludeJobSteps
            $Results[0].PSObject.Properties.Name | Should -Contain 'StartDate'
            $Results[0].PSObject.Properties.Name | Should -Contain 'EndDate'
            $Results[0].PSObject.Properties.Name | Should -Contain 'Duration'
        }

        It 'Returns "augmented" properties that are correct' {
            $Results = Get-DbaAgentJobHistory -ExcludeJobSteps
            $Results[0].StartDate | Should -Be $Results[0].RunDate
            $Results[0].RunDuration | Should -Be 112
            $Results[0].Duration.TotalSeconds | Should -Be 72
            $Results[0].EndDate | Should -Be ($Results[0].StartDate.AddSeconds($Results[0].Duration.TotalSeconds))
        }

        It "Figures out plain outputfiles" {
            $Results = Get-DbaAgentJobHistory -WithOutputFile
            ($Results | Where-Object StepID -eq 0).Count | Should -Be 2
            ($Results | Where-Object StepID -eq 0).OutputFileName -Join '' | Should -BeNullOrEmpty
            ($Results | Where-Object StepID -ne 0 | Where-Object JobName -eq 'Job1').OutputFileName | Should -Match 'Job1Output[12]'
            ($Results | Where-Object StepID -eq 2 | Where-Object JobName -eq 'Job2').OutputFileName | Should -Match 'Job2Output1'
            ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job2').OutputFileName | Should -BeNullOrEmpty
        }
    }

    Context "SQL Agent Tokens" {
        BeforeAll {
            $tokenTests = @(
                @{ Token = 'INST'; Expected = 'BASEServiceName' },
                @{ Token = 'MACH'; Expected = 'BASEComputerName' },
                @{ Token = 'SQLDIR'; Expected = 'BASEInstallDataDirectory' },
                @{ Token = 'SQLLOGDIR'; Expected = 'BASEErrorLog_''_"_]_Path' },
                @{ Token = 'SRVR'; Expected = 'BASEDomainInstanceName' },
                @{ Token = 'STEPID'; Expected = '1' },
                @{ Token = 'JOBID'; Expected = '0x848A71E7438BD0468F8D4FC4464F9FC5' },
                @{ Token = 'STRTDT'; Expected = '20170926' },
                @{ Token = 'STRTTM'; Expected = '130000' },
                @{ Token = 'DATE'; Expected = '20170926' },
                @{ Token = 'TIME'; Expected = '130001' }
            )
        }

        It "Handles <Token>" -TestCases $tokenTests {
            param($Token, $Expected)
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = 'Job1'
                        StepId         = 1
                        OutputFileName = "`$($Token)__Job1Output1"
                    }
                )
            }
            $Results = Get-DbaAgentJobHistory -WithOutputFile
            ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job1').OutputFileName | Should -Be "$Expected`__Job1Output1"
        }
    }

    Context "SQL Agent escape sequences" {
        BeforeAll {
            $escapeTests = @(
                @{ Escape = 'ESCAPE_NONE'; Expected = 'BASEErrorLog_''_"_]_Path' },
                @{ Escape = 'ESCAPE_SQUOTE'; Expected = 'BASEErrorLog_''''_"_]_Path' },
                @{ Escape = 'ESCAPE_DQUOTE'; Expected = 'BASEErrorLog_''_""_]_Path' },
                @{ Escape = 'ESCAPE_RBRACKET'; Expected = 'BASEErrorLog_''_"_]]_Path' }
            )
        }

        It "Handles <Escape>" -TestCases $escapeTests {
            param($Escape, $Expected)
            Mock Get-DbaAgentJobOutputFile -MockWith {
                @(
                    @{
                        Job            = 'Job1'
                        StepId         = 1
                        OutputFileName = "`$($Escape(SQLLOGDIR))__Job1Output1"
                    }
                )
            }
            $Results = Get-DbaAgentJobHistory -WithOutputFile
            ($Results | Where-Object StepID -eq 1 | Where-Object JobName -eq 'Job1').OutputFileName | Should -Be "$Expected`__Job1Output1"
        }
    }
}

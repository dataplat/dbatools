param($ModuleName = 'dbatools')

Describe "Set-DbaAgentServer" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $testServer = $script:instance2
        $random = Get-Random
        $mailProfileName = "dbatoolsci_$random"
        $mailProfile = New-DbaDbMailProfile -SqlInstance $testServer -Name $mailProfileName
    }

    AfterAll {
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXECUTE msdb.dbo.sysmail_delete_profile_sp @profile_name = '$mailProfileName'"
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC msdb.dbo.sp_set_sqlagent_properties @local_host_server=N''"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAgentServer
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type JobServer[] -Not -Mandatory
        }
        It "Should have AgentLogLevel as a parameter" {
            $CommandUnderTest | Should -HaveParameter AgentLogLevel -Type Object -Not -Mandatory
        }
        It "Should have AgentMailType as a parameter" {
            $CommandUnderTest | Should -HaveParameter AgentMailType -Type Object -Not -Mandatory
        }
        It "Should have AgentShutdownWaitTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter AgentShutdownWaitTime -Type Int32 -Not -Mandatory
        }
        It "Should have DatabaseMailProfile as a parameter" {
            $CommandUnderTest | Should -HaveParameter DatabaseMailProfile -Type String -Not -Mandatory
        }
        It "Should have ErrorLogFile as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorLogFile -Type String -Not -Mandatory
        }
        It "Should have IdleCpuDuration as a parameter" {
            $CommandUnderTest | Should -HaveParameter IdleCpuDuration -Type Int32 -Not -Mandatory
        }
        It "Should have IdleCpuPercentage as a parameter" {
            $CommandUnderTest | Should -HaveParameter IdleCpuPercentage -Type Int32 -Not -Mandatory
        }
        It "Should have CpuPolling as a parameter" {
            $CommandUnderTest | Should -HaveParameter CpuPolling -Type String -Not -Mandatory
        }
        It "Should have LocalHostAlias as a parameter" {
            $CommandUnderTest | Should -HaveParameter LocalHostAlias -Type String -Not -Mandatory
        }
        It "Should have LoginTimeout as a parameter" {
            $CommandUnderTest | Should -HaveParameter LoginTimeout -Type Int32 -Not -Mandatory
        }
        It "Should have MaximumHistoryRows as a parameter" {
            $CommandUnderTest | Should -HaveParameter MaximumHistoryRows -Type Int32 -Not -Mandatory
        }
        It "Should have MaximumJobHistoryRows as a parameter" {
            $CommandUnderTest | Should -HaveParameter MaximumJobHistoryRows -Type Int32 -Not -Mandatory
        }
        It "Should have NetSendRecipient as a parameter" {
            $CommandUnderTest | Should -HaveParameter NetSendRecipient -Type String -Not -Mandatory
        }
        It "Should have ReplaceAlertTokens as a parameter" {
            $CommandUnderTest | Should -HaveParameter ReplaceAlertTokens -Type String -Not -Mandatory
        }
        It "Should have SaveInSentFolder as a parameter" {
            $CommandUnderTest | Should -HaveParameter SaveInSentFolder -Type String -Not -Mandatory
        }
        It "Should have SqlAgentAutoStart as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlAgentAutoStart -Type String -Not -Mandatory
        }
        It "Should have SqlAgentMailProfile as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlAgentMailProfile -Type String -Not -Mandatory
        }
        It "Should have SqlAgentRestart as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlAgentRestart -Type String -Not -Mandatory
        }
        It "Should have SqlServerRestart as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlServerRestart -Type String -Not -Mandatory
        }
        It "Should have WriteOemErrorLog as a parameter" {
            $CommandUnderTest | Should -HaveParameter WriteOemErrorLog -Type String -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Command usage" {
        It "changes agent server job history properties to 10000 / 100" {
            $results = Set-DbaAgentServer -SqlInstance $testServer -MaximumHistoryRows 10000 -MaximumJobHistoryRows 100
            $results.MaximumHistoryRows | Should -Be 10000
            $results.MaximumJobHistoryRows | Should -Be 100
            $results.JobHistoryIsEnabled | Should -Be $true
        }

        It "disable max history and then enables it again" {
            $results = Set-DbaAgentServer -SqlInstance $testServer -MaximumHistoryRows -1 -MaximumJobHistoryRows 0
            $results.MaximumHistoryRows | Should -Be -1
            $results.MaximumJobHistoryRows | Should -Be 0
            $results.JobHistoryIsEnabled | Should -Be $false

            $results = Set-DbaAgentServer -SqlInstance $testServer -MaximumHistoryRows 10000 -MaximumJobHistoryRows 100
            $results.MaximumHistoryRows | Should -Be 10000
            $results.MaximumJobHistoryRows | Should -Be 100
            $results.JobHistoryIsEnabled | Should -Be $true
        }

        It "changes agent server CPU Polling to true" {
            $results = Set-DbaAgentServer -SqlInstance $testServer -CpuPolling Enabled
            $results.IsCpuPollingEnabled | Should -Be $true
        }

        It "changes agent server CPU Polling to false" {
            $results = Set-DbaAgentServer -SqlInstance $testServer -CpuPolling Disabled
            $results.IsCpuPollingEnabled | Should -Be $false
        }

        It "AgentLogLevel" {
            $results = Set-DbaAgentServer -SqlInstance $testServer -AgentLogLevel "Errors"
            $results.AgentLogLevel | Should -Be "Errors"

            $results = Set-DbaAgentServer -SqlInstance $testServer -AgentLogLevel "Warnings"
            $results.AgentLogLevel | Should -Be "Warnings"

            $results = Set-DbaAgentServer -SqlInstance $testServer -AgentLogLevel "Errors, Warnings"
            $results.AgentLogLevel | Should -Be "Errors, Warnings"

            $results = Set-DbaAgentServer -SqlInstance $testServer -AgentLogLevel "Informational"
            $results.AgentLogLevel | Should -Be "Informational"

            $results = Set-DbaAgentServer -SqlInstance $testServer -AgentLogLevel "Errors, Informational"
            $results.AgentLogLevel | Should -Be "Errors, Informational"

            $results = Set-DbaAgentServer -SqlInstance $testServer -AgentLogLevel "Warnings, Informational"
            $results.AgentLogLevel | Should -Be "Warnings, Informational"

            $results = Set-DbaAgentServer -SqlInstance $testServer -AgentLogLevel "All"
            $results.AgentLogLevel | Should -Be "All"
        }

        It "AgentMailType" {
            $results = Set-DbaAgentServer -SqlInstance $testServer -AgentMailType "SqlAgentMail"
            $results.AgentMailType | Should -BeIn @("DatabaseMail", "SqlAgentMail") # SQL 2019 returns "SqlAgentMail" but SQL 2016 and 2017 return "DatabaseMail"

            $results = Set-DbaAgentServer -SqlInstance $testServer -AgentMailType "DatabaseMail"
            $results.AgentMailType | Should -Be "DatabaseMail"
        }

        It "AgentShutdownWaitTime" {
            $results = Set-DbaAgentServer -SqlInstance $testServer -AgentShutdownWaitTime 599
            $results.AgentShutdownWaitTime | Should -Be 599
        }

        It "DatabaseMailProfile" {
            $results = Set-DbaAgentServer -SqlInstance $testServer -DatabaseMailProfile $mailProfileName
            $results.DatabaseMailProfile | Should -Be $mailProfileName
        }

        It "ErrorLogFile" {
            $agentServer = Get-DbaAgentServer -SqlInstance $testServer
            $results = Set-DbaAgentServer -SqlInstance $testServer -ErrorLogFile "$($agentServer.ErrorLogFile).log"
            $results.ErrorLogFile | Should -Be "$($agentServer.ErrorLogFile).log"

            $results = Set-DbaAgentServer -SqlInstance $testServer -ErrorLogFile $agentServer.ErrorLogFile
            $results.ErrorLogFile | Should -Be $agentServer.ErrorLogFile
        }

        It "IdleCpuDuration" {
            $results = Set-DbaAgentServer -SqlInstance $testServer -IdleCpuDuration 86399
            $results.IdleCpuDuration | Should -Be 86399
        }

        It "IdleCpuPercentage" {
            $results = Set-DbaAgentServer -SqlInstance $testServer -IdleCpuPercentage 99
            $results.IdleCpuPercentage | Should -Be 99
        }

        It "LocalHostAlias" {
            $results = Set-DbaAgentServer -SqlInstance $testServer -LocalHostAlias "localhost"
            $results.LocalHostAlias | Should -Be "localhost"
        }

        It "LoginTimeout" {
            $agentServer = Get-DbaAgentServer -SqlInstance $testServer
            $results = Set-DbaAgentServer -SqlInstance $testServer -LoginTimeout 30
            $results.LoginTimeout | Should -Be 30

            $results = Set-DbaAgentServer -SqlInstance $testServer -LoginTimeout $agentServer.LoginTimeout
            $results.LoginTimeout | Should -Be $agentServer.LoginTimeout
        }

        It "NetSendRecipient" {
            $agentServer = Get-DbaAgentServer -SqlInstance $testServer
            $results = Set-DbaAgentServer -SqlInstance $testServer -NetSendRecipient "dbatoolsci_$random"
            $results.NetSendRecipient | Should -Be "dbatoolsci_$random"

            $results = Set-DbaAgentServer -SqlInstance $testServer -NetSendRecipient $agentServer.NetSendRecipient
            $results.NetSendRecipient | Should -Be $agentServer.NetSendRecipient
        }

        It "ReplaceAlertTokens" {
            $agentServer = Get-DbaAgentServer -SqlInstance $testServer
            $results = Set-DbaAgentServer -SqlInstance $testServer -ReplaceAlertTokens Enabled
            $results.ReplaceAlertTokensEnabled | Should -Be $true

            $results = Set-DbaAgentServer -SqlInstance $testServer -ReplaceAlertTokens Disabled
            $results.ReplaceAlertTokensEnabled | Should -Be $false

            if ($agentServer.ReplaceAlertTokensEnabled) {
                $results = Set-DbaAgentServer -SqlInstance $testServer -ReplaceAlertTokens Enabled
                $results.ReplaceAlertTokensEnabled | Should -Be $true
            } else {
                $results = Set-DbaAgentServer -SqlInstance $testServer -ReplaceAlertTokens Disabled
                $results.ReplaceAlertTokensEnabled | Should -Be $false
            }
        }

        It "SaveInSentFolder" {
            $agentServer = Get-DbaAgentServer -SqlInstance $testServer
            $results = Set-DbaAgentServer -SqlInstance $testServer -SaveInSentFolder Enabled
            $results.SaveInSentFolder | Should -Be $true

            $results = Set-DbaAgentServer -SqlInstance $testServer -SaveInSentFolder Disabled
            $results.SaveInSentFolder | Should -Be $false

            if ($agentServer.SaveInSentFolder) {
                $results = Set-DbaAgentServer -SqlInstance $testServer -SaveInSentFolder Enabled
                $results.SaveInSentFolder | Should -Be $true
            } else {
                $results = Set-DbaAgentServer -SqlInstance $testServer -SaveInSentFolder Disabled
                $results.SaveInSentFolder | Should -Be $false
            }
        }

        It "SqlAgentMailProfile" {
            $agentServer = Get-DbaAgentServer -SqlInstance $testServer
            $results = Set-DbaAgentServer -SqlInstance $testServer -SqlAgentMailProfile "dbatoolsci_$random"
            $results.SqlAgentMailProfile | Should -Be "dbatoolsci_$random"

            $results = Set-DbaAgentServer -SqlInstance $testServer -SqlAgentMailProfile $agentServer.SqlAgentMailProfile
            $results.SqlAgentMailProfile | Should -Be $agentServer.SqlAgentMailProfile
        }

        It "SqlAgentRestart" {
            $results = Set-DbaAgentServer -SqlInstance $testServer -SqlAgentRestart Disabled
            $results.SqlAgentRestart | Should -Be $false

            $results = Set-DbaAgentServer -SqlInstance $testServer -SqlAgentRestart Enabled
            $results.SqlAgentRestart | Should -Be $true
        }

        It "SqlServerRestart" {
            $results = Set-DbaAgentServer -SqlInstance $testServer -SqlServerRestart Disabled
            $results.SqlServerRestart | Should -Be $false

            $results = Set-DbaAgentServer -SqlInstance $testServer -SqlServerRestart Enabled
            $results.SqlServerRestart | Should -Be $true
        }

        It "WriteOemErrorLog" {
            $results = Set-DbaAgentServer -SqlInstance $testServer -WriteOemErrorLog Enabled
            $results.WriteOemErrorLog | Should -Be $true

            $results = Set-DbaAgentServer -SqlInstance $testServer -WriteOemErrorLog Disabled
            $results.WriteOemErrorLog | Should -Be $false
        }

        It "set values outside of the expected ranges for MaximumHistoryRows" {
            $results = Set-DbaAgentServer -SqlInstance $testServer -MaximumHistoryRows 1000000
            $results | Should -BeNullOrEmpty

            $results = Set-DbaAgentServer -SqlInstance $testServer -MaximumHistoryRows 1
            $results | Should -BeNullOrEmpty
        }

        It "set values outside of the expected ranges for MaximumJobHistoryRows" {
            $results = Set-DbaAgentServer -SqlInstance $testServer -MaximumJobHistoryRows 1000000
            $results | Should -BeNullOrEmpty

            $results = Set-DbaAgentServer -SqlInstance $testServer -MaximumJobHistoryRows 1
            $results | Should -BeNullOrEmpty
        }

        It "set values outside of the expected ranges for AgentShutdownWaitTime" {
            { Set-DbaAgentServer -SqlInstance $testServer -AgentShutdownWaitTime 601 } | Should -Throw
            { Set-DbaAgentServer -SqlInstance $testServer -AgentShutdownWaitTime 4 } | Should -Throw
        }

        It "set values outside of the expected ranges for IdleCpuDuration" {
            { Set-DbaAgentServer -SqlInstance $testServer -IdleCpuDuration 86401 } | Should -Throw
            { Set-DbaAgentServer -SqlInstance $testServer -IdleCpuDuration 19 } | Should -Throw
        }

        It "set values outside of the expected ranges for IdleCpuPercentage" {
            { Set-DbaAgentServer -SqlInstance $testServer -IdleCpuPercentage 101 } | Should -Throw
            { Set-DbaAgentServer -SqlInstance $testServer -IdleCpuPercentage 9 } | Should -Throw
        }

        It "set values outside of the expected ranges for LoginTimeout" {
            { Set-DbaAgentServer -SqlInstance $testServer -LoginTimeout 4 } | Should -Throw
            { Set-DbaAgentServer -SqlInstance $testServer -LoginTimeout 50 } | Should -Throw
        }
    }

    Context "SqlAgentAutoStart" -Skip:([Environment]::GetEnvironmentVariable('appveyor')) {
        It "SqlAgentAutoStart" {
            $agentServer = Get-DbaAgentServer -SqlInstance $testServer
            $results = Set-DbaAgentServer -SqlInstance $testServer -SqlAgentAutoStart Enabled
            $results.SqlAgentAutoStart | Should -Be $true

            $results = Set-DbaAgentServer -SqlInstance $testServer -SqlAgentAutoStart Disabled
            $results.SqlAgentAutoStart | Should -Be $false

            if ($agentServer.SqlAgentAutoStart) {
                $results = Set-DbaAgentServer -SqlInstance $testServer -SqlAgentAutoStart Enabled
                $results.SqlAgentAutoStart | Should -Be $true
            } else {
                $results = Set-DbaAgentServer -SqlInstance $testServer -SqlAgentAutoStart Disabled
                $results.SqlAgentAutoStart | Should -Be $false
            }
        }
    }
}

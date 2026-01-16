#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgentServer",
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
                "InputObject",
                "AgentLogLevel",
                "AgentMailType",
                "AgentShutdownWaitTime",
                "DatabaseMailProfile",
                "ErrorLogFile",
                "IdleCpuDuration",
                "IdleCpuPercentage",
                "CpuPolling",
                "LocalHostAlias",
                "LoginTimeout",
                "MaximumHistoryRows",
                "MaximumJobHistoryRows",
                "NetSendRecipient",
                "ReplaceAlertTokens",
                "SaveInSentFolder",
                "SqlAgentAutoStart",
                "SqlAgentMailProfile",
                "SqlAgentRestart",
                "SqlServerRestart",
                "WriteOemErrorLog",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $testServer = $TestConfig.InstanceSingle
        $random = Get-Random
        $mailProfileName = "dbatoolsci_$random"
        $mailProfile = New-DbaDbMailProfile -SqlInstance $testServer -Name $mailProfileName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXECUTE msdb.dbo.sysmail_delete_profile_sp @profile_name = '$mailProfileName'"
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC msdb.dbo.sp_set_sqlagent_properties @local_host_server=N''"

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

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

    # Unable to do this test locally:  RegCreateKeyEx() returned error 5, 'Access is denied.'
    It -Skip "SqlAgentAutoStart" {
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
        $results = Set-DbaAgentServer -SqlInstance $testServer -MaximumHistoryRows 1000000 -WarningAction SilentlyContinue
        $WarnVar | Should -Match "You must specify a MaximumHistoryRows value"
        $results | Should -BeNull

        $results = Set-DbaAgentServer -SqlInstance $testServer -MaximumHistoryRows 1 -WarningAction SilentlyContinue
        $WarnVar | Should -Match "You must specify a MaximumHistoryRows value"
        $results | Should -BeNull
    }

    It "set values outside of the expected ranges for MaximumJobHistoryRows" {
        $results = Set-DbaAgentServer -SqlInstance $testServer -MaximumJobHistoryRows 1000000 -WarningAction SilentlyContinue
        $WarnVar | Should -Match "You must specify a MaximumJobHistoryRows value"
        $results | Should -BeNull

        $results = Set-DbaAgentServer -SqlInstance $testServer -MaximumJobHistoryRows 1 -WarningAction SilentlyContinue
        $WarnVar | Should -Match "You must specify a MaximumJobHistoryRows value"
        $results | Should -BeNull
    }

    It "set values outside of the expected ranges for AgentShutdownWaitTime" {
        $validationError = $false;
        try {
            Set-DbaAgentServer -SqlInstance $testServer -AgentShutdownWaitTime 601
        } catch {
            $validationError = $true
        }
        $validationError | Should -Be $true

        $validationError = $false;
        try {
            Set-DbaAgentServer -SqlInstance $testServer -AgentShutdownWaitTime 4
        } catch {
            $validationError = $true
        }
        $validationError | Should -Be $true
    }

    It "set values outside of the expected ranges for IdleCpuDuration" {
        $validationError = $false;
        try {
            Set-DbaAgentServer -SqlInstance $testServer -IdleCpuDuration 86401
        } catch {
            $validationError = $true
        }
        $validationError | Should -Be $true

        $validationError = $false;
        try {
            Set-DbaAgentServer -SqlInstance $testServer -IdleCpuDuration 19
        } catch {
            $validationError = $true
        }
        $validationError | Should -Be $true
    }

    It "set values outside of the expected ranges for IdleCpuPercentage" {
        $validationError = $false;
        try {
            Set-DbaAgentServer -SqlInstance $testServer -IdleCpuPercentage 101
        } catch {
            $validationError = $true
        }
        $validationError | Should -Be $true

        $validationError = $false;
        try {
            Set-DbaAgentServer -SqlInstance $testServer -IdleCpuPercentage 9
        } catch {
            $validationError = $true
        }
        $validationError | Should -Be $true
    }

    It "set values outside of the expected ranges for LoginTimeout" {
        $validationError = $false;
        try {
            Set-DbaAgentServer -SqlInstance $testServer -LoginTimeout 4
        } catch {
            $validationError = $true
        }
        $validationError | Should -Be $true

        $validationError = $false;
        try {
            Set-DbaAgentServer -SqlInstance $testServer -LoginTimeout 50
        } catch {
            $validationError = $true
        }
        $validationError | Should -Be $true
    }
}
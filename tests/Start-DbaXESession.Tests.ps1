#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Start-DbaXESession",
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
                "Session",
                "StartAt",
                "StopAt",
                "AllSessions",
                "InputObject",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $conn = $server.ConnectionContext
        # Get the systemhealth session
        $systemhealth = Get-DbaXESession -SqlInstance $server -Session system_health
        # Create a session with an invalid target
        $conn.ExecuteNonQuery("CREATE EVENT SESSION [dbatoolsci_session_invalid] ON SERVER ADD EVENT sqlserver.lock_acquired ADD TARGET package0.etw_classic_sync_target (SET default_etw_session_logfile_path = N'C:\dbatoolsci_session_doesnotexist\logfile.etl' );")
        $dbatoolsciInvalid = Get-DbaXESession -SqlInstance $server -Session dbatoolsci_session_invalid
        # Create a valid session
        $conn.ExecuteNonQuery("CREATE EVENT SESSION [dbatoolsci_session_valid] ON SERVER ADD EVENT sqlserver.lock_acquired;")
        $dbatoolsciValid = Get-DbaXESession -SqlInstance $server -Session dbatoolsci_session_valid
        # Record the Status of all sessions
        $allSessions = Get-DbaXESession -SqlInstance $server

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    BeforeEach {
        $systemhealth.Refresh()
        if ($systemhealth.IsRunning) {
            $systemhealth.Stop()
        }
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set the Status of all session back to what they were before the test
        foreach ($session in $allSessions) {
            $session.Refresh()
            if ($session.Status -eq "Stopped") {
                if ($session.IsRunning) {
                    $session.Stop()
                }
            } else {
                if (-Not $session.IsRunning) {
                    $session.Start()
                }
            }
        }

        # Drop created objects
        $conn.ExecuteNonQuery("IF EXISTS(SELECT * FROM sys.server_event_sessions WHERE name = 'dbatoolsci_session_invalid') DROP EVENT SESSION [dbatoolsci_session_invalid] ON SERVER;")
        $conn.ExecuteNonQuery("IF EXISTS(SELECT * FROM sys.server_event_sessions WHERE name = 'dbatoolsci_session_valid') DROP EVENT SESSION [dbatoolsci_session_valid] ON SERVER;")
        Get-DbaAgentSchedule -SqlInstance $TestConfig.instance2 -Schedule "XE Session START - dbatoolsci_session_valid", "XE Session STOP - dbatoolsci_session_valid" | Remove-DbaAgentSchedule -Force -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Verifying command works" {
        It "starts the system_health session" {
            $systemhealth | Start-DbaXESession
            $systemhealth.Refresh()
            $systemhealth.IsRunning | Should -Be $true
        }

        It "does not change state if XE session is already started" {
            if (-Not $systemhealth.IsRunning) {
                $systemhealth.Start()
            }
            $systemhealth | Start-DbaXESession -WarningAction SilentlyContinue
            $systemhealth.Refresh()
            $systemhealth.IsRunning | Should -Be $true
        }

        It "starts the other XE Sessions when one has an error" {
            # Start system_health and the invalid session
            Start-DbaXESession $server -Session $systemhealth.Name, $dbatoolsciInvalid.Name -WarningAction SilentlyContinue
            $systemhealth.Refresh()
            $dbatoolsciInvalid.Refresh()
            $systemhealth.IsRunning | Should -Be $true
            $dbatoolsciInvalid.IsRunning | Should -Be $false
        }

        It "starts all XE Sessions except the system ones if -AllSessions is used" {
            Start-DbaXESession $server -AllSessions -WarningAction SilentlyContinue
            $systemhealth.Refresh()
            $dbatoolsciValid.Refresh()
            $systemhealth.IsRunning | Should -Be $false
            $dbatoolsciValid.IsRunning | Should -Be $true
        }

        It "works when -StopAt is passed" {
            $StopAt = (Get-Date).AddSeconds(10)
            Start-DbaXESession $server -Session $dbatoolsciValid.Name -StopAt $StopAt -WarningAction SilentlyContinue
            $dbatoolsciValid.Refresh()
            $dbatoolsciValid.IsRunning | Should -Be $true
            (Get-DbaAgentJob -SqlInstance $server -Job "XE Session STOP - dbatoolsci_session_valid").Count | Should -Be 1
            $stopSchedule = Get-DbaAgentSchedule -SqlInstance $server -Schedule "XE Session STOP - dbatoolsci_session_valid"
            $stopSchedule.ActiveStartTimeOfDay.ToString("hhmmss") | Should -Be $StopAt.TimeOfDay.ToString("hhmmss")
            $stopSchedule.ActiveStartDate | Should -Be $StopAt.Date
            Start-Sleep -Seconds 11
            $dbatoolsciValid.Refresh()
            $dbatoolsciValid.IsRunning | Should -Be $false
            # Using $TestConfig.instance2 because the SMO $server is not updated after the job is removed
            (Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job "XE Session STOP - dbatoolsci_session_valid").Count | Should -Be 0
        }

        It "works when -StartAt is passed" {
            $null = Stop-DbaXESession -SqlInstance $server -Session $dbatoolsciValid.Name -WarningAction SilentlyContinue
            $StartAt = (Get-Date).AddSeconds(10)
            $null = Start-DbaXESession $server -Session $dbatoolsciValid.Name -StartAt $StartAt
            $dbatoolsciValid.Refresh()
            $dbatoolsciValid.IsRunning | Should -Be $false
            (Get-DbaAgentJob -SqlInstance $server -Job "XE Session START - dbatoolsci_session_valid").Count | Should -Be 1
            $startSchedule = Get-DbaAgentSchedule -SqlInstance $server -Schedule "XE Session START - dbatoolsci_session_valid"
            $startSchedule.ActiveStartTimeOfDay.ToString("hhmmss") | Should -Be $StartAt.TimeOfDay.ToString("hhmmss")
            $startSchedule.ActiveStartDate | Should -Be $StartAt.Date
            Start-Sleep -Seconds 11
            $dbatoolsciValid.Refresh()
            $dbatoolsciValid.IsRunning | Should -Be $true
            # Using $TestConfig.instance2 because the SMO $server is not updated after the job is removed
            (Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job "XE Session STOP - dbatoolsci_session_valid").Count | Should -Be 0
        }
    }
}
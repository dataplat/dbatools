#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Stop-DbaXESession",
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
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        # Create a valid session and start it
        $server.Query("CREATE EVENT SESSION [dbatoolsci_session_valid] ON SERVER ADD EVENT sqlserver.lock_acquired;")
        $dbatoolsciValid = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session dbatoolsci_session_valid
        $dbatoolsciValid.Start()
        # Record the Status of all sessions
        $allSessions = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle
    }
    BeforeEach {
        $dbatoolsciValid.Refresh()
        if (-Not $dbatoolsciValid.IsRunning) {
            $dbatoolsciValid.Start()
        }
    }
    AfterAll {
        # Set the Status of all session back to what they were before the test
        foreach ($session in $allSessions) {
            $session.Refresh()
            if ($session.Status -eq "Stopped") {
                if ($session.IsRunning) {
                    $session | Stop-DbaXESession
                }
            } else {
                if (-Not $session.IsRunning) {
                    $session | Start-DbaXESession
                }
            }
        }

        # Drop created objects
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $server.Query("IF EXISTS(SELECT * FROM sys.server_event_sessions WHERE name = 'dbatoolsci_session_valid') DROP EVENT SESSION [dbatoolsci_session_valid] ON SERVER;")
    }

    Context "Command execution and functionality" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        }

        It "stops the system_health session" {
            $dbatoolsciValid | Stop-DbaXESession
            $dbatoolsciValid.Refresh()
            $dbatoolsciValid.IsRunning | Should -Be $false
        }

        It "does not change state if XE session is already stopped" {
            if ($dbatoolsciValid.IsRunning) {
                $dbatoolsciValid.Stop()
            }
            Stop-DbaXESession -SqlInstance $server -Session $dbatoolsciValid.Name -WarningAction SilentlyContinue
            $dbatoolsciValid.Refresh()
            $dbatoolsciValid.IsRunning | Should -Be $false
        }

        It "stops all XE Sessions except the system ones if -AllSessions is used" {
            Stop-DbaXESession $server -AllSessions -WarningAction SilentlyContinue
            $dbatoolsciValid.Refresh()
            $dbatoolsciValid.IsRunning | Should -Be $false
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When stopping sessions repeatedly" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Stop() used to make SFC reconnect the store connection that Get-DbaXESession had returned,
            # and nothing returned it again: one new session on the instance per stopped session (#10658).
            # Count the sessions of this process through a server object opened once, because a per-call
            # counting command would open connections of its own. Every status is counted, not only
            # sleeping: a pooled session flips between sleeping and dormant around a reset, which made a
            # sleeping-only count move by one without any new session.
            $countServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $countQuery = @"
select count(*)
from sys.dm_exec_sessions
where host_process_id = $PID
  and session_id <> @@spid
"@
            # The session is started through the counting connection between the rounds, so that only
            # the command under test touches the store.
            $countSession = "dbatoolsci_session_count_$(Get-Random)"
            $startQuery = "ALTER EVENT SESSION [$countSession] ON SERVER STATE = START;"
            $countServer.Query("CREATE EVENT SESSION [$countSession] ON SERVER ADD EVENT sqlserver.lock_acquired;")

            # One warm-up round of each form so the pooled connections they need exist before the
            # baseline is taken.
            $countServer.Query($startQuery)
            $null = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session $countSession | Stop-DbaXESession
            $countServer.Query($startQuery)
            $null = Stop-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session $countSession
            $sessionsBefore = $countServer.ConnectionContext.ExecuteScalar($countQuery)

            foreach ($i in 1..3) {
                $countServer.Query($startQuery)
                $null = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session $countSession | Stop-DbaXESession
            }
            $sessionsAfterPipeline = $countServer.ConnectionContext.ExecuteScalar($countQuery)

            foreach ($i in 1..3) {
                $countServer.Query($startQuery)
                $null = Stop-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session $countSession
            }
            $sessionsAfterParameter = $countServer.ConnectionContext.ExecuteScalar($countQuery)

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $countServer.Query("IF EXISTS (SELECT * FROM sys.server_event_sessions WHERE name = '$countSession') DROP EVENT SESSION [$countSession] ON SERVER;")
            $countServer.ConnectionContext.Disconnect()

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Leaves no session behind when the sessions come from the pipeline" {
            $sessionsAfterPipeline | Should -Be $sessionsBefore
        }

        It "Leaves no session behind when the instance is given" {
            $sessionsAfterParameter | Should -Be $sessionsBefore
        }
    }
}
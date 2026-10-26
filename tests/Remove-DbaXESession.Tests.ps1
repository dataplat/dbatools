#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaXESession",
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
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session 'Profiler TSQL Duration' | Remove-DbaXESession

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session 'Profiler TSQL Duration' | Remove-DbaXESession

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Test Importing Session Template" {
        BeforeAll {
            $results = Import-DbaXESessionTemplate -SqlInstance $TestConfig.InstanceSingle -Template 'Profiler TSQL Duration'
        }

        It "session should exist" {
            $results.Name | Should -BeExactly 'Profiler TSQL Duration'
        }

        It "session should no longer exist after removal" {
            $null = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session 'Profiler TSQL Duration' | Remove-DbaXESession
            $removedResults = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session 'Profiler TSQL Duration'
            $removedResults.Name | Should -BeNullOrEmpty
            $removedResults.Status | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When removing sessions repeatedly" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Drop() used to make SFC reconnect the store connection that Get-DbaXESession had returned,
            # and nothing returned it again: one new session on the instance per removed session (#10658).
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
            # The session is created through the counting connection before every round, so that only
            # the command under test touches the store.
            $countSession = "dbatoolsci_session_count_$(Get-Random)"
            $createQuery = "CREATE EVENT SESSION [$countSession] ON SERVER ADD EVENT sqlserver.lock_acquired;"

            # One warm-up round of each form so the pooled connections they need exist before the
            # baseline is taken.
            $countServer.Query($createQuery)
            $null = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session $countSession | Remove-DbaXESession
            $countServer.Query($createQuery)
            $null = Remove-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session $countSession
            $sessionsBefore = $countServer.ConnectionContext.ExecuteScalar($countQuery)

            foreach ($i in 1..3) {
                $countServer.Query($createQuery)
                $null = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session $countSession | Remove-DbaXESession
            }
            $sessionsAfterPipeline = $countServer.ConnectionContext.ExecuteScalar($countQuery)

            foreach ($i in 1..3) {
                $countServer.Query($createQuery)
                $null = Remove-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session $countSession
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
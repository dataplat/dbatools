#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaXESession",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Verifying command output" {
        It "returns some results" {
            $results = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle
            $results.Count -gt 1 | Should -Be $true
        }

        It "returns only the system_health session" {
            $results = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health
            $results.Name -eq "system_health" | Should -Be $true
        }
    }

    Context "When querying sessions repeatedly" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The command used to leave the cloned connection of its XEStore open, one new sleeping
            # session per call. Count sessions through a server object opened once, because a per-call
            # counting command would open connections of its own.
            $countServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $countQuery = @"
select count(*)
from sys.dm_exec_sessions
where program_name like 'dbatools%'
  and status = 'sleeping'
  and session_id <> @@spid
"@

            # One warm-up call so the shared pooled connection exists before the baseline is taken.
            $null = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health
            $sleepingBefore = $countServer.ConnectionContext.ExecuteScalar($countQuery)

            foreach ($i in 1..3) {
                $null = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health
            }
            $sleepingAfter = $countServer.ConnectionContext.ExecuteScalar($countQuery)

            # Early pipeline termination stops the command in the middle of its emission loop, so
            # a disconnect placed after the loop never runs on this path - only a finally covers it.
            foreach ($i in 1..3) {
                $null = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle | Select-Object -First 1
            }
            $sleepingAfterEarlyEnd = $countServer.ConnectionContext.ExecuteScalar($countQuery)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $countServer.ConnectionContext.Disconnect()
        }

        It "Leaves no sleeping session behind" {
            $sleepingAfter | Should -Be $sleepingBefore
        }

        It "Leaves no sleeping session behind when the pipeline ends early" {
            $sleepingAfterEarlyEnd | Should -Be $sleepingBefore
        }

        It "Emits objects whose store still works after the connection is returned" {
            $result = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health
            # The store must transparently reconnect for downstream commands like Start or Stop.
            $result.Store.Sessions.Name | Should -Contain "system_health"
            # The assertion above deliberately reopened the store connection - return it, so this
            # test does not leave shared connection state behind for later tests to trip over.
            $result.Store.SfcConnection.Disconnect()
        }
    }
}
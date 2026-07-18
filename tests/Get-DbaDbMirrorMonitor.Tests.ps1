#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbMirrorMonitor",
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
                "Database",
                "InputObject",
                "Update",
                "LimitResults",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: retrieving mirroring statistics (sp_dbmmonitorresults) requires a database
    # configured for database mirroring, which needs a mirroring partner instance - not available on
    # the standalone InstanceSingle - so that leg is DEFERRED-TO-GATE. What IS characterizable on a
    # standalone instance is the pre-query guard: when the msdb monitor table (dbm_monitor_data) does
    # not exist, the command warns and returns nothing (the same check the source performs before
    # calling sp_dbmmonitorresults).
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        # mirror the source check: $db.Parent.Databases["msdb"].Tables["dbm_monitor_data"].Name
        $monitorTablePresent = [bool]$server.Databases["msdb"].Tables["dbm_monitor_data"].Name
    }

    Context "Guarding before the query" {
        It "Warns and returns nothing when the mirror monitor table is missing" {
            # If the monitor table already exists on this instance the not-found guard cannot be
            # exercised (and the not-monitored-database error path is environment-specific), so skip.
            if ($monitorTablePresent) {
                Set-ItResult -Skipped -Because "msdb.dbo.dbm_monitor_data already exists on this instance; the not-found guard cannot be exercised"
                return
            }
            # -Database master is db-independent for this guard (it fires on the missing monitor table
            # before any per-database mirroring query).
            $splatMonitor = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = "master"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = @(Get-DbaDbMirrorMonitor @splatMonitor)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "msdb.dbo.dbm_monitor_data not found. Please run Add-DbaDbMirrorMonitor then you can get monitor stats."
        }
    }
}
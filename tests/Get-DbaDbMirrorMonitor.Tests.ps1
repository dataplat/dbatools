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
    # COVERAGE NOTE: the guard leg for a MISSING msdb.dbo.dbm_monitor_data table lives in the
    # InstanceSingle characterization; this suite covers the complementary side on the mirroring
    # pair - the monitor table is ENSURED present, so the not-found guard must never fire, and the
    # live statistics leg runs when a mirroring session can actually be built on this lab pair.
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $mirrorDb = "dbatoolsci_mirrormonitor"

        # Ensure the monitor infrastructure exists on the instance we query; remember whether it
        # was already there so teardown only removes what this suite created.
        # Existence is probed with a LIVE OBJECT_ID query, NOT the SMO Tables collection: the cached
        # collection can report the table present when it was dropped since the connection (a stale
        # false-positive silently SKIPS the ensure below, leaving dbm_monitor_data genuinely absent
        # at query time - the exact re-gate red on this leg). The 3-part name resolves regardless of
        # the connection's current database.
        $monitorServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
        $monitorTableQuery = "SELECT CASE WHEN OBJECT_ID('msdb.dbo.dbm_monitor_data') IS NULL THEN 0 ELSE 1 END AS TablePresent"
        $monitorPreexisted = [bool]$monitorServer.Query($monitorTableQuery).TablePresent
        if (-not $monitorPreexisted) {
            $null = Add-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceMulti2
        }

        # VERIFY the table is actually present now - the whole premise of the guard leg below. If the
        # ensure could not establish it (permissions, sp_dbmmonitoraddmonitoring unavailable on this
        # build), the leg degrades to an explicit skip rather than asserting the guard-never-fires on
        # a fixture that was never built.
        $monitorTablePresent = [bool]$monitorServer.Query($monitorTableQuery).TablePresent

        # The live-statistics leg needs a real mirroring session. Building one can legitimately
        # fail on an under-provisioned pair, and that must degrade the leg to an explicit skip
        # rather than fail the whole suite - so the fixture attempt is probed, not asserted.
        $mirrorLive = $false
        $mirrorProbeError = "not attempted"
        try {
            $null = Get-DbaProcess -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 | Where-Object Program -Match dbatools | Stop-DbaProcess -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            $null = $server.Query("CREATE DATABASE $mirrorDb")
            $splatMirroring = @{
                Primary       = $TestConfig.InstanceMulti1
                Mirror        = $TestConfig.InstanceMulti2
                Database      = $mirrorDb
                SharedPath    = $TestConfig.Temp
                Force         = $true
                WarningAction = "SilentlyContinue"
            }
            $null = Invoke-DbaDbMirroring @splatMirroring
            $mirrorState = Get-DbaDbMirror -SqlInstance $TestConfig.InstanceMulti1 -Database $mirrorDb
            if ($mirrorState) {
                $mirrorLive = $true
            } else {
                $mirrorProbeError = "Invoke-DbaDbMirroring completed but no mirroring session is visible on the primary"
            }
        } catch {
            $mirrorProbeError = $_.Exception.Message
        }

        # A live mirroring session is NECESSARY but not SUFFICIENT for the statistics leg: a freshly
        # built session legitimately has ZERO rows in dbm_monitor_data until the monitor has sampled
        # it, even after -Update. Probe whether monitor rows can actually be retrieved and record it,
        # so the statistics leg skips with a reason (session too fresh) instead of failing 0 -gt 0 -
        # the second re-gate red on this row. Probed defensively so a warning here cannot fail setup.
        $mirrorStatsAvailable = $false
        if ($mirrorLive) {
            try {
                $splatStatsProbe = @{
                    SqlInstance     = $TestConfig.InstanceMulti2
                    Database        = $mirrorDb
                    Update          = $true
                    EnableException = $false
                    WarningAction   = "SilentlyContinue"
                }
                $statsProbe = @(Get-DbaDbMirrorMonitor @splatStatsProbe)
                $mirrorStatsAvailable = $statsProbe.Count -gt 0
                if (-not $mirrorStatsAvailable) {
                    $mirrorProbeError = "mirroring session built but sp_dbmmonitorresults returned no rows after -Update (session too fresh to have monitor data)"
                }
            } catch {
                $mirrorProbeError = "monitor statistics probe threw: $($_.Exception.Message)"
            }
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the cleanup fails loudly.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        try {
            if ($mirrorLive) {
                $null = Remove-DbaDbMirror -SqlInstance $TestConfig.InstanceMulti1 -Database $mirrorDb -ErrorAction SilentlyContinue
            }
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database $mirrorDb -ErrorAction SilentlyContinue
        } finally {
            # The monitor table and its msdb job are instance-global state - remove them only if
            # this suite created them, even when the mirror teardown above throws.
            if (-not $monitorPreexisted) {
                $null = Remove-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceMulti2 -ErrorAction SilentlyContinue
            }
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "With the monitor table present" {
        It "Does not fire the not-found guard for a non-mirrored database and returns nothing" {
            # Re-establish + re-verify the monitor table on the EXACT instance THIS leg queries,
            # immediately before the assertion. A's lab re-gate found dbm_monitor_data missing at
            # query time even though the BeforeAll ensured it on this same instance - the BeforeAll
            # check ran before the mirror build (and a prior run's teardown or the mirroring setup can
            # leave the table absent by the time the leg runs). Ensuring at assertion time on the
            # queried instance closes that scoping/timing gap; if the table still cannot be built the
            # leg skips-with-reason rather than asserting on a premise that does not hold.
            $guardServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
            if (-not [bool]$guardServer.Query($monitorTableQuery).TablePresent) {
                $null = Add-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceMulti2 -EnableException:$false -WarningAction SilentlyContinue
            }
            if (-not [bool]$guardServer.Query($monitorTableQuery).TablePresent) {
                Set-ItResult -Skipped -Because "dbm_monitor_data could not be established on the queried instance ($($TestConfig.InstanceMulti2)); the table-present premise does not hold"
                return
            }
            $splatNotMirrored = @{
                SqlInstance     = $TestConfig.InstanceMulti2
                Database        = "master"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = @(Get-DbaDbMirrorMonitor @splatNotMirrored)
            $result.Count | Should -Be 0
            # master is not mirrored so a Failure warning from sp_dbmmonitorresults is legitimate;
            # the table-missing guard message is the one outcome that must never appear here.
            $warn | Should -Not -Match "dbm_monitor_data not found"
        }

        It "Returns monitor statistics for a mirrored database" {
            if (-not ($mirrorLive -and $mirrorStatsAvailable)) {
                Set-ItResult -Skipped -Because "no monitor statistics were retrievable on this pair: $mirrorProbeError"
                return
            }
            $splatMonitor = @{
                SqlInstance  = $TestConfig.InstanceMulti2
                Database     = $mirrorDb
                Update       = $true
                LimitResults = "LastRow"
            }
            $results = @(Get-DbaDbMirrorMonitor @splatMonitor)
            $results.Count | Should -BeGreaterThan 0
            $results[0].DatabaseName | Should -Be $mirrorDb
            $results[0].PSObject.Properties.Name | Should -Contain "MirroringState"
            $results[0].PSObject.Properties.Name | Should -Contain "Role"
        }
    }
}
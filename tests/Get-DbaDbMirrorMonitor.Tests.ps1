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

            # A run that died mid-fixture leaves $mirrorDb behind - ONLINE on the primary and
            # RESTORING on the mirror - and CREATE DATABASE then throws "already exists". The catch
            # below turns that into a permanent SKIP of the statistics leg rather than a failure, so
            # the leg silently never runs again on this pair (found exactly that way: the leftover
            # dated from an earlier interrupted run and every gate since had skipped). Purge any
            # leftover on BOTH instances first so the fixture build is idempotent. Best-effort: a
            # clean pair has nothing to remove and must not fail setup.
            $null = Remove-DbaDbMirror -SqlInstance $TestConfig.InstanceMulti1 -Database $mirrorDb -EnableException:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $splatPurge = @{
                SqlInstance     = $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
                Database        = $mirrorDb
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $null = Remove-DbaDatabase @splatPurge

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

        # Build REAL monitor data for the leg below, so that leg tests the command rather than an
        # empty monitor table. Two facts, both measured on this pair rather than assumed:
        # sp_dbmmonitorresults reports rates BETWEEN consecutive samples, so it needs TWO rows in
        # dbm_monitor_data (one sample returns 0 results, the second returns 1), and
        # sp_dbmmonitorupdate ignores calls made less than ~15 seconds apart, so samples must be
        # spaced past that floor or every extra call is a silent no-op. Driven with raw T-SQL
        # deliberately: the command's own -Update cannot be used to establish the premise for a
        # test of the command. Probed defensively so a failure here cannot fail setup.
        $monitorDataRows = 0
        if ($mirrorLive) {
            try {
                $sampleServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
                foreach ($sample in 1..2) {
                    $null = $sampleServer.Query("EXEC msdb.dbo.sp_dbmmonitorupdate")
                    if ($sample -lt 2) {
                        Start-Sleep -Seconds 20
                    }
                }
                $monitorDataRows = [int]$sampleServer.Query("SELECT COUNT(*) AS RowCountValue FROM msdb.dbo.dbm_monitor_data WHERE database_id = DB_ID('$mirrorDb')").RowCountValue
                if ($monitorDataRows -lt 2) {
                    $mirrorProbeError = "only $monitorDataRows monitor sample(s) accumulated for $mirrorDb; sp_dbmmonitorresults needs two to report"
                }
            } catch {
                $mirrorProbeError = "monitor sampling threw: $($_.Exception.Message)"
            }
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the cleanup fails loudly.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        try {
            # EnableException is $true here, which makes dbatools commands THROW regardless of
            # -ErrorAction. Removing the mirror and dropping the database therefore need separate
            # try/catch: with both in one block a throwing Remove-DbaDbMirror skipped the drop and
            # leaked $mirrorDb onto the pair, which then made every later run skip the statistics
            # leg (the leftover found on this pair got there exactly that way). The drop must run
            # even when the mirror teardown fails.
            if ($mirrorLive) {
                try {
                    $null = Remove-DbaDbMirror -SqlInstance $TestConfig.InstanceMulti1 -Database $mirrorDb -ErrorAction SilentlyContinue
                } catch {
                    Write-Warning -Message "Mirror teardown failed, continuing to the database drop: $($PSItem.Exception.Message)"
                }
            }
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database $mirrorDb -ErrorAction SilentlyContinue
        } finally {
            # The monitor table and its msdb job are instance-global state - remove them only if
            # this suite created them, even when the mirror teardown above throws.
            if (-not $monitorPreexisted) {
                $null = Remove-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceMulti2 -ErrorAction SilentlyContinue
            }

            # Invoke-DbaDbMirroring creates a "Mirroring" DBM endpoint on BOTH instances to
            # establish the session, and removing the mirror does not remove it. specs/lab-requirements.md
            # requires the Multi instances to be endpoint-free and LAB-12 enforces it, so leaving the
            # endpoint behind fails preflight on every run and trains everyone to ignore it (LAB-02
            # drift went unnoticed for 14 days that way). In the finally so it runs even when the
            # mirror teardown above throws.
            $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 |
                Where-Object EndpointType -eq DatabaseMirroring |
                Remove-DbaEndpoint -ErrorAction SilentlyContinue

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

        It "Characterizes the bracket-quoted database name sent to sp_dbmmonitorresults" {
            # CHARACTERIZATION OF A LIVE BUG - this asserts what the command DOES, not what it
            # should do. The source interpolates the SMO database OBJECT into the T-SQL string
            # ("@database_name = '$db'"), and SMO's Database.ToString() renders "[name]", so the
            # procedure is handed '[dbatoolsci_mirrormonitor]' - a literal that never matches a
            # database. Statistics retrieval therefore returns NOTHING and warns, on every mirrored
            # database, and always has. Verified on this pair: the same sp_dbmmonitorresults call
            # with the PLAIN name returns a row, so the monitor data is present and it is purely the
            # bracket quoting that fails. The behavior is identical in the PowerShell source and the
            # compiled cmdlet, so the port is FAITHFUL - this is an upstream dbatools bug, tracked
            # on the campaign's source-bug register, not a conversion defect.
            #
            # When the upstream bug is fixed this test goes RED. That is the point of a
            # characterization test: replace it then with the real statistics assertion.
            if (-not $mirrorLive -or $monitorDataRows -lt 2) {
                Set-ItResult -Skipped -Because "the mirroring fixture could not be established on this pair: $mirrorProbeError"
                return
            }
            $splatMonitor = @{
                SqlInstance     = $TestConfig.InstanceMulti2
                Database        = $mirrorDb
                Update          = $true
                LimitResults    = "LastRow"
                WarningVariable = "statsWarn"
                WarningAction   = "SilentlyContinue"
            }
            $results = @(Get-DbaDbMirrorMonitor @splatMonitor)
            $results.Count | Should -Be 0
            # The bracketed name is the distinguishing evidence - a generic failure would not prove
            # the quoting is the cause.
            ($statsWarn -join " ") | Should -BeLike "*[[]$mirrorDb[]]*does not exist*"
        }
    }
}
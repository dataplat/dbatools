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
        $monitorServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
        $monitorPreexisted = [bool]$monitorServer.Databases["msdb"].Tables["dbm_monitor_data"].Name
        if (-not $monitorPreexisted) {
            $null = Add-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceMulti2
        }

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
            if (-not $mirrorLive) {
                Set-ItResult -Skipped -Because "no mirroring session could be built on this pair: $mirrorProbeError"
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
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgBackupHistory",
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
                "AvailabilityGroup",
                "Database",
                "ExcludeDatabase",
                "IncludeCopyOnly",
                "Force",
                "Since",
                "RecoveryFork",
                "Last",
                "LastFull",
                "LastDiff",
                "LastLog",
                "DeviceType",
                "Raw",
                "LastLsn",
                "IncludeMirror",
                "Type",
                "LsnSort",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

# No Integration Tests, because we don't have an availability group running in AppVeyor

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: retrieving backup history across Availability Group replicas requires a live
    # Availability Group, which the standalone InstanceSingle does not provide - that leg is
    # DEFERRED-TO-AG01 per the coordinator AG policy (a read-only smoke against the lab's AG01 supplies
    # the integration evidence). What IS characterizable on a standalone instance is the pre-retrieval
    # guard: with a mandatory -AvailabilityGroup that does not exist, the command skips the instance
    # (per-instance warning) and finishes without results (end-block warning), emitting nothing.
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $hasAvailabilityGroups = $server.AvailabilityGroups.Count -gt 0
        $random = Get-Random
        $instanceToken = "$([DbaInstanceParameter]$TestConfig.InstanceSingle)"
        # [char]39 supplies the single quotes the source wraps the AG name in, without putting
        # forbidden single quotes in the test source.
        $q = [char]39
    }

    Context "Guarding before retrieval" {
        It "Warns twice and returns nothing when the requested Availability Group is absent" {
            $agName = "dbatoolsci_noag_$random"
            $splatHistory = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = $agName
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
            }
            $result = @(Get-DbaAgBackupHistory @splatHistory)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 2

            # strip Write-Message's bracketed [timestamp]/[function] prefix from each warning
            $payloads = $warn | ForEach-Object { $PSItem.Message -replace "^(\[[^\]]*\]\s*)+", "" }

            # the end-block guard always fires when no instance carried the group
            $expectedEnd = "No instances with availability group named ${q}${agName}${q} found, so finishing without results."
            $payloads | Should -Contain $expectedEnd

            # the per-instance guard message depends on whether the instance has any AGs at all
            if ($hasAvailabilityGroups) {
                $expectedPerInstance = "Instance $instanceToken has no availability group named ${q}${agName}${q}, so skipping."
            } else {
                $expectedPerInstance = "Instance $instanceToken has no availability groups, so skipping."
            }
            $payloads | Should -Contain $expectedPerInstance
        }
    }
}
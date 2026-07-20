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
    # DEFERRED-TO-AG01 per the coordinator AG policy (a read-only smoke against AG01 in the lab supplies
    # the integration evidence). What IS characterizable on a standalone instance is the pre-retrieval
    # guard: with a mandatory -AvailabilityGroup that does not exist, the command skips the instance
    # (per-instance warning) and finishes without results (end-block warning), emitting nothing.
    BeforeAll {
        # No setup connection and no AG-state snapshot: on a shared lab instance the AG inventory
        # can change between a snapshot and the call under test, so the warning assertion below
        # accepts whichever of the two valid per-instance payloads matches the instance's state AT
        # CALL TIME. A GUID (not Get-Random) makes the requested name's absence a certainty.
        $absentAgName = "dbatoolsci_noag_$(([guid]::NewGuid()).ToString("N"))"
        $instanceToken = "$([DbaInstanceParameter]$TestConfig.InstanceSingle)"
        # [char]39 supplies the single quotes the source wraps the AG name in, without putting
        # forbidden single quotes in the test source.
        $q = [char]39
    }

    Context "Guarding before retrieval" {
        It "Warns twice and returns nothing when the requested Availability Group is absent" {
            $agName = $absentAgName
            $splatHistory = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = $agName
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
            }
            $result = @(Get-DbaAgBackupHistory @splatHistory)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 2

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from each warning
            $payloads = $warn | ForEach-Object { $PSItem.Message -replace "^(\[[^\]]*\]\s*)+", "" }

            # the end-block guard always fires when no instance carried the group
            $expectedEnd = "No instances with availability group named ${q}${agName}${q} found, so finishing without results."
            $payloads | Should -Contain $expectedEnd

            # the per-instance guard message depends on whether the instance has any AGs at all -
            # a state this suite deliberately does not snapshot (shared-lab race); exactly one of
            # the two valid payloads must be present.
            $namedSkip = "Instance $instanceToken has no availability group named ${q}${agName}${q}, so skipping."
            $bareSkip = "Instance $instanceToken has no availability groups, so skipping."
            @($payloads | Where-Object { $PSItem -eq $namedSkip -or $PSItem -eq $bareSkip }).Count | Should -Be 1
        }
    }
}
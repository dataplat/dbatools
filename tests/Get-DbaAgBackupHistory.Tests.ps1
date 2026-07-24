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
    # This block covers the pre-retrieval guard: with a mandatory -AvailabilityGroup that does not
    # exist, the command skips the instance (per-instance warning) and finishes without results
    # (end-block warning), emitting nothing. Retrieval against a live group is covered by the block
    # further down.
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

<#
    LIVE RETRIEVAL COVERAGE. Backup history is only retrievable if backups exist, so this suite
    seeds its own: one ordinary full and one copy-only full of an Availability Group database, taken
    on the replica that currently holds it and sent to the NUL device. NUL still writes the msdb
    history row the command reads, and leaves no file behind to reclaim.

    The last leg is the one the guard block cannot reach. Instances accumulate across process
    records into a list the end block inspects, and the LIST LENGTH changes the meaning of the
    call: a single instance is treated as a listener and expanded into every replica of the group,
    while two or more are queried as given. Only a multi-record pipe can show the difference.
#>
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Discover a >=2-replica AG on any reachable HADR instance. The AG has no dedicated TestConfig
        # key (it is a persistent lab fixture), so resolve it dynamically. Every instance role is a
        # candidate, InstanceSingle included: whether a role is HADR-enabled and carries a
        # multi-replica group is a property of the lab, not of the role name.
        $agReady = $false
        $agSkipReason = $null
        $agInstance = $null
        $resolvedAg = $null
        $agDatabase = $null
        $secondaryReplicas = @()

        try {
            $candidates = @($TestConfig.InstanceSingle, $TestConfig.InstanceHadr, $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2) | Where-Object { $PSItem } | Select-Object -Unique
            foreach ($candidate in $candidates) {
                $candidateServer = Connect-DbaInstance -SqlInstance $candidate
                if (-not $candidateServer.IsHadrEnabled) {
                    continue
                }
                $multiReplicaAg = Get-DbaAvailabilityGroup -SqlInstance $candidateServer | Where-Object { $PSItem.AvailabilityReplicas.Count -ge 2 -and $PSItem.AvailabilityDatabases.Count -ge 1 } | Select-Object -First 1
                if ($multiReplicaAg) {
                    $agInstance = $candidate
                    $resolvedAg = $multiReplicaAg.Name
                    $agDatabase = @($multiReplicaAg.AvailabilityDatabases.Name)[0]
                    $secondaryReplicas = @($multiReplicaAg.AvailabilityReplicas | Where-Object Role -ne "Primary" | ForEach-Object { $PSItem.Name })
                    $agReady = $true
                    break
                }
            }
            if (-not $agReady) {
                $agSkipReason = "no reachable instance hosts a >=2-replica availability group with a database in it"
            }
        } catch {
            $agSkipReason = "availability-group discovery failed: $($PSItem.Exception.Message)"
        }

        if ($agReady) {
            # Seed the history the command is supposed to find. Both backups are taken where the
            # database currently lives; each writes its own msdb row, and only the copy-only one is
            # filtered out by default.
            $splatOrdinaryBackup = @{
                SqlInstance = $agInstance
                Database    = $agDatabase
                Type        = "Full"
                FilePath    = "NUL"
            }
            $null = Backup-DbaDatabase @splatOrdinaryBackup
            $splatCopyOnlyBackup = @{
                SqlInstance = $agInstance
                Database    = $agDatabase
                Type        = "Full"
                CopyOnly    = $true
                FilePath    = "NUL"
            }
            $null = Backup-DbaDatabase @splatCopyOnlyBackup
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Retrieving from a live availability group" {
        It "Returns the seeded backup, stamped with the availability group name" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            # Every row is re-stamped with the requested group name before it is emitted - that stamp
            # is the command's whole contribution over Get-DbaDbBackupHistory, and it is what the
            # guard-only coverage could never observe.
            $rows = @(Get-DbaAgBackupHistory -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)
            $rows.Count | Should -BeGreaterThan 0
            foreach ($row in $rows) {
                $row.AvailabilityGroupName | Should -Be $resolvedAg
                $row.Database | Should -Be $agDatabase
            }
            @($rows | Where-Object Type -eq "Full").Count | Should -BeGreaterThan 0
        }

        It "Omits copy-only backups unless -IncludeCopyOnly is supplied" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            # The suite seeded one of each, so the copy-only row must be absent by default and
            # present with the switch.
            $defaultRows = @(Get-DbaAgBackupHistory -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)
            $copyOnlyRows = @(Get-DbaAgBackupHistory -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -IncludeCopyOnly -WarningAction SilentlyContinue)

            @($defaultRows | Where-Object IsCopyOnly -eq $true).Count | Should -Be 0
            @($copyOnlyRows | Where-Object IsCopyOnly -eq $true).Count | Should -BeGreaterThan 0
            $copyOnlyRows.Count | Should -BeGreaterThan $defaultRows.Count
        }

        It "Expands a single instance into the whole group but queries several as given" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            if ($secondaryReplicas.Count -lt 2) {
                Set-ItResult -Skipped -Because "the group has fewer than two secondary replicas, so the expansion and the as-given path cannot be told apart"
                return
            }
            # ONE secondary in: the end block treats it as a listener and queries every replica, so
            # the history taken on the PRIMARY comes back even though the primary was never named.
            $expanded = @($secondaryReplicas[0] | Get-DbaAgBackupHistory -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)
            @($expanded | Where-Object { "$($PSItem.SqlInstance)" -ne $secondaryReplicas[0] }).Count | Should -BeGreaterThan 0

            # TWO secondaries in: no expansion, so the primary is never queried and none of its rows
            # can appear.
            $asGiven = @($secondaryReplicas | Get-DbaAgBackupHistory -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)
            @($asGiven | Where-Object { "$($PSItem.SqlInstance)" -notin $secondaryReplicas }).Count | Should -Be 0
        }
    }
}
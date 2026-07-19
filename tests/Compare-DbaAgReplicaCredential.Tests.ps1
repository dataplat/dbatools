#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAgReplicaCredential",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: the core behavior (comparing credentials across 2+ Availability Group
    # replicas) requires a live multi-replica Availability Group, which the standalone InstanceSingle
    # does not provide. Per the coordinator AG policy that leg is DEFERRED-TO-AG01 (a read-only
    # Get/Compare smoke against the lab's AG01 supplies the integration evidence). What IS
    # characterizable on a standalone instance is the pre-comparison guard: the command connects and,
    # before any comparison, warns and returns nothing when the instance is not HADR-enabled, or when
    # no Availability Group matches the requested name.
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $isHadrEnabled = $server.IsHadrEnabled
        $random = Get-Random
    }

    Context "Guarding before the comparison" {
        It "Warns and returns nothing when there is nothing to compare on the instance" {
            # A non-existent Availability Group name exercises the guard regardless of the instance's
            # HADR state: a non-HADR instance warns that HADR is not configured; an HADR instance
            # without that AG warns that no matching group was found. Either way, no object is emitted
            # and the live replica comparison is never reached.
            $splatCompare = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = "dbatoolsci_noag_$random"
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
            }
            $result = @(Compare-DbaAgReplicaCredential @splatCompare)
            $result.Count | Should -Be 0
            $joinedWarn = $warn -join " "
            if ($isHadrEnabled) {
                $joinedWarn | Should -Match "No Availability Groups found on .* matching the specified criteria"
            } else {
                $joinedWarn | Should -Match "Availability Group \(HADR\) is not configured for the instance"
            }
        }
    }
}

<#
    AG01 READ-ONLY SMOKE (authored per the coordinator's zero-test ruling: author now, a lab seat with
    a live multi-replica Availability Group runs it later). Compare-DbaAgReplicaCredential compares SQL
    Server credentials ACROSS AG replicas, so it needs a real >=2-replica AG - the standalone
    InstanceSingle cannot resolve a second replica. This suite DISCOVERS a >=2-replica AG on a HADR
    instance and skips-with-reason if none is provisioned; it never fails over or mutates the AG
    topology (read-only). The one fixture it creates - a disposable dbatoolsci_ credential on a single
    replica, to force a detectable difference - is torn down on attempt, exactly by its randomized name.
#>
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Run setup with EnableException so a genuine fixture failure surfaces rather than a silent skip.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Discover a >=2-replica AG on any reachable HADR instance. AG01 has no dedicated TestConfig key
        # (it is a persistent lab AG), so resolve it dynamically and skip if the topology is not present.
        $agReady = $false
        $agSkipReason = $null
        $agInstance = $null
        $resolvedAg = $null
        $replicaInstances = @()

        # Disposable divergence fixture, torn down by exact name whether or not resolution completed.
        $probeCredName = "dbatoolsci_agcredcmp_$(Get-Random)"
        $probeCredCreatedOn = $null

        try {
            $candidates = @($TestConfig.InstanceHadr, $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2) | Where-Object { $PSItem } | Select-Object -Unique
            foreach ($candidate in $candidates) {
                $candidateServer = Connect-DbaInstance -SqlInstance $candidate
                if (-not $candidateServer.IsHadrEnabled) {
                    continue
                }
                $multiReplicaAg = Get-DbaAvailabilityGroup -SqlInstance $candidateServer | Where-Object { $PSItem.AvailabilityReplicas.Count -ge 2 } | Select-Object -First 1
                if ($multiReplicaAg) {
                    $agInstance = $candidate
                    $resolvedAg = $multiReplicaAg.Name
                    $replicaInstances = @($multiReplicaAg.AvailabilityReplicas.Name)
                    $agReady = $true
                    break
                }
            }
            if (-not $agReady) {
                $agSkipReason = "no reachable HADR instance hosts a >=2-replica availability group (AG01 not provisioned on this lab)"
            }
        } catch {
            $agSkipReason = "availability-group discovery failed: $($_.Exception.Message)"
        }

        # Warnings must be observable in the It blocks, so drop EnableException before the tests run.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        try {
            if ($probeCredCreatedOn) {
                $null = Remove-DbaCredential -SqlInstance $probeCredCreatedOn -Credential $probeCredName -Confirm:$false -ErrorAction SilentlyContinue
            }
        } finally {
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "Against a multi-replica availability group (read-only)" {
        It "Runs against a live AG and every emitted row has the documented shape" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            # Pure read-only: whatever difference rows the AG's current credential configuration
            # produces, each must carry the documented columns and a valid Status. An identically
            # configured AG emits zero rows, which is also valid - the shape contract is what this pins.
            $rows = @(Compare-DbaAgReplicaCredential -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)
            foreach ($row in $rows) {
                $row.PSObject.Properties.Name | Should -Contain "AvailabilityGroup"
                $row.PSObject.Properties.Name | Should -Contain "Replica"
                $row.PSObject.Properties.Name | Should -Contain "CredentialName"
                $row.PSObject.Properties.Name | Should -Contain "Status"
                $row.PSObject.Properties.Name | Should -Contain "Identity"
                $row.Status | Should -BeIn @("Present", "Missing")
                $row.AvailabilityGroup | Should -Be $resolvedAg
            }
        }

        It "Reports a credential present on only one replica as Missing on the others" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            # Inject a disposable credential on ONE replica only (credential state, not AG topology) so
            # the comparison has a deterministic difference to surface. Set the teardown flag before the
            # create so a mid-setup throw still reclaims it.
            $probeCredCreatedOn = $replicaInstances[0]
            $probeIdentity = "dbatoolsci\$probeCredName"
            $probeSecret = ConvertTo-SecureString -String "dbatools.IO!$(Get-Random)" -AsPlainText -Force
            $null = New-DbaCredential -SqlInstance $probeCredCreatedOn -Name $probeCredName -Identity $probeIdentity -SecurePassword $probeSecret -EnableException

            $rows = @(Compare-DbaAgReplicaCredential -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)
            $probeRows = @($rows | Where-Object CredentialName -eq $probeCredName)

            # The credential exists on exactly one replica, so at least one OTHER replica must report it
            # Missing.
            $probeRows.Count | Should -BeGreaterThan 0
            ($probeRows | Where-Object Status -eq "Missing").Count | Should -BeGreaterThan 0
            $probeRows[0].AvailabilityGroup | Should -Be $resolvedAg
        }
    }
}

#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAgReplicaLogin",
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
                "ExcludeSystemLogin",
                "IncludeModifiedDate",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # This block covers the pre-comparison guard: the command connects and, before any comparison,
    # warns and returns nothing when the instance is not HADR-enabled, or when no Availability Group
    # matches the requested name. The comparison itself is covered by the live multi-replica block
    # further down.
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
            $result = @(Compare-DbaAgReplicaLogin @splatCompare)
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
    LIVE MULTI-REPLICA COVERAGE. Comparing logins ACROSS replicas is the whole point of this
    command, and it can only be exercised against a real >=2-replica Availability Group. This suite
    DISCOVERS one on a reachable HADR instance and skips-with-reason if none is provisioned; it
    never fails over or mutates the AG topology (read-only). The one fixture it creates - a
    disposable dbatoolsci_ login on a single replica, to force a detectable difference - is torn
    down on attempt, exactly by its randomized name.
#>
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Run setup with EnableException so a genuine fixture failure surfaces rather than a silent skip.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Discover a >=2-replica AG on any reachable HADR instance. The AG has no dedicated TestConfig
        # key (it is a persistent lab fixture), so resolve it dynamically. Every instance role is a
        # candidate, InstanceSingle included: whether a role is HADR-enabled and carries a
        # multi-replica group is a property of the lab, not of the role name.
        $agReady = $false
        $agSkipReason = $null
        $agInstance = $null
        $resolvedAg = $null
        $replicaInstances = @()

        # Disposable divergence fixture, torn down by exact name whether or not resolution completed.
        $probeLoginName = "dbatoolsci_aglogincmp_$(Get-Random)"
        $script:probeLoginCreatedOn = $null

        try {
            $candidates = @($TestConfig.InstanceSingle, $TestConfig.InstanceHadr, $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2) | Where-Object { $PSItem } | Select-Object -Unique
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
                $agSkipReason = "no reachable instance hosts a >=2-replica availability group"
            }
        } catch {
            $agSkipReason = "availability-group discovery failed: $($PSItem.Exception.Message)"
        }

        # Warnings must be observable in the It blocks, so drop EnableException before the tests run.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        try {
            if ($script:probeLoginCreatedOn) {
                $null = Remove-DbaLogin -SqlInstance $script:probeLoginCreatedOn -Login $probeLoginName -Confirm:$false -ErrorAction SilentlyContinue
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
            # Pure read-only: whatever difference rows the AG's current login configuration produces,
            # each must carry the documented columns and a valid Status. An identically-configured AG
            # emits zero rows, which is also valid - the shape contract is what this leg pins.
            $rows = @(Compare-DbaAgReplicaLogin -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)
            foreach ($row in $rows) {
                $row.PSObject.Properties.Name | Should -Contain "AvailabilityGroup"
                $row.PSObject.Properties.Name | Should -Contain "Replica"
                $row.PSObject.Properties.Name | Should -Contain "LoginName"
                $row.PSObject.Properties.Name | Should -Contain "Status"
                $row.PSObject.Properties.Name | Should -Contain "ModifyDate"
                $row.PSObject.Properties.Name | Should -Contain "CreateDate"
                $row.Status | Should -BeIn @("Present", "Missing")
                $row.AvailabilityGroup | Should -Be $resolvedAg
            }
        }

        It "Reports a login present on only one replica as Missing on the others" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            # Inject a disposable login on ONE replica only (login state, not AG topology) so the
            # comparison has a deterministic difference to surface. Set the teardown flag before the
            # create so a mid-setup throw still reclaims it.
            $script:probeLoginCreatedOn = $replicaInstances[0]
            $probeSecret = ConvertTo-SecureString -String "dbatools.IO!$(Get-Random)" -AsPlainText -Force
            $null = New-DbaLogin -SqlInstance $script:probeLoginCreatedOn -Login $probeLoginName -SecurePassword $probeSecret -EnableException

            $rows = @(Compare-DbaAgReplicaLogin -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)
            $probeRows = @($rows | Where-Object LoginName -eq $probeLoginName)

            # The login exists on exactly one replica, so at least one OTHER replica must report it
            # Missing. Without -IncludeModifiedDate the command emits ONLY the Missing side of a
            # difference - the replica that HAS the login contributes no row at all.
            $probeRows.Count | Should -BeGreaterThan 0
            @($probeRows | Where-Object Status -eq "Missing").Count | Should -Be $probeRows.Count
            $probeRows.Replica | Should -Not -Contain $script:probeLoginCreatedOn
            $probeRows[0].AvailabilityGroup | Should -Be $resolvedAg
        }

        It "Adds the Present side of the difference under -IncludeModifiedDate" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            # -IncludeModifiedDate is what turns Present replicas into emitted rows, carrying the
            # modify_date read from sys.server_principals. The probe login from the previous leg is
            # present on exactly one replica, so it must now surface both sides.
            $rows = @(Compare-DbaAgReplicaLogin -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -IncludeModifiedDate -WarningAction SilentlyContinue)
            $probeRows = @($rows | Where-Object LoginName -eq $probeLoginName)

            $presentRows = @($probeRows | Where-Object Status -eq "Present")
            $presentRows.Count | Should -BeGreaterThan 0
            $presentRows[0].Replica | Should -Be $script:probeLoginCreatedOn
            $presentRows[0].ModifyDate | Should -Not -BeNullOrEmpty
            @($probeRows | Where-Object Status -eq "Missing").Count | Should -BeGreaterThan 0
        }
    }
}

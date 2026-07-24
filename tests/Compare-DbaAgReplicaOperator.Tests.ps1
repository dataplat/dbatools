#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAgReplicaOperator",
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
            $result = @(Compare-DbaAgReplicaOperator @splatCompare)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1
            # the command interpolates "$instance" (the bound DbaInstanceParameter) into the message;
            # reproduce that exact token and strip Write-Message's bracketed [timestamp]/[function]
            # prefix so the full message can be compared exactly (no extra/erroneous warnings).
            $instanceToken = "$([DbaInstanceParameter]$TestConfig.InstanceSingle)"
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            if ($isHadrEnabled) {
                $payload | Should -Be "No Availability Groups found on $instanceToken matching the specified criteria."
            } else {
                $payload | Should -Be "Availability Group (HADR) is not configured for the instance: $instanceToken."
            }
        }
    }
}

<#
    LIVE MULTI-REPLICA COVERAGE. Comparing operators ACROSS replicas is the whole point of this
    command, and it can only be exercised against a real >=2-replica Availability Group. This suite
    DISCOVERS one on a reachable HADR instance and skips-with-reason if none is provisioned; it
    never fails over or mutates the AG topology (read-only against the topology). The fixtures it
    creates are disposable dbatoolsci_ SQL Agent operators, torn down on attempt by exact name.

    Operators are the family member whose emission predicate has TWO arms - a name missing from a
    replica, OR the same name carrying different email addresses across replicas - so the legs below
    pin both arms and the suppression case where neither holds.
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

        # Disposable fixtures, torn down by exact name whether or not resolution completed.
        $operatorSuffix = Get-Random
        $missingOperator = "dbatoolsci_agopmissing_$operatorSuffix"
        $driftOperator = "dbatoolsci_agopdrift_$operatorSuffix"
        $matchedOperator = "dbatoolsci_agopmatched_$operatorSuffix"
        $script:operatorFixtureReplicas = @()

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
        # Reclaim every operator this suite could have created, on every replica it could have
        # created it on. Names are randomized, so a stale match is impossible.
        foreach ($fixtureReplica in $script:operatorFixtureReplicas) {
            foreach ($fixtureName in @($missingOperator, $driftOperator, $matchedOperator)) {
                $splatRemoveOperator = @{
                    SqlInstance   = $fixtureReplica
                    Operator      = $fixtureName
                    Confirm       = $false
                    ErrorAction   = "SilentlyContinue"
                    WarningAction = "SilentlyContinue"
                }
                $null = Remove-DbaAgentOperator @splatRemoveOperator
            }
        }
    }

    Context "Against a multi-replica availability group" {
        It "Runs against a live AG and every emitted row has the documented shape" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            # Pure read-only: whatever difference rows the AG's current operator configuration
            # produces, each must carry the documented columns and a valid Status. An
            # identically-configured AG emits zero rows, which is also valid - the shape contract is
            # what this leg pins.
            $rows = @(Compare-DbaAgReplicaOperator -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)
            foreach ($row in $rows) {
                $row.PSObject.Properties.Name | Should -Contain "AvailabilityGroup"
                $row.PSObject.Properties.Name | Should -Contain "Replica"
                $row.PSObject.Properties.Name | Should -Contain "OperatorName"
                $row.PSObject.Properties.Name | Should -Contain "Status"
                $row.PSObject.Properties.Name | Should -Contain "EmailAddress"
                $row.Status | Should -BeIn @("Present", "Missing")
                $row.AvailabilityGroup | Should -Be $resolvedAg
            }
        }

        It "Emits both sides when an operator exists on only one replica" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            # Record the teardown targets before creating anything, so a mid-setup throw still
            # reclaims whatever landed.
            $script:operatorFixtureReplicas = $replicaInstances
            $splatNewOperator = @{
                SqlInstance     = $replicaInstances[0]
                Operator        = $missingOperator
                EmailAddress    = "missing@dbatools.io"
                EnableException = $true
            }
            $null = New-DbaAgentOperator @splatNewOperator

            $rows = @(Compare-DbaAgReplicaOperator -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)
            $probeRows = @($rows | Where-Object OperatorName -eq $missingOperator)

            # Unlike the login comparer, this one emits the Present side too: the replica that HAS
            # the operator gets a row carrying its email, and every other replica gets a Missing row
            # with a null email.
            $present = @($probeRows | Where-Object Status -eq "Present")
            $missing = @($probeRows | Where-Object Status -eq "Missing")
            $present.Count | Should -Be 1
            $present[0].Replica | Should -Be $replicaInstances[0]
            $present[0].EmailAddress | Should -Be "missing@dbatools.io"
            $missing.Count | Should -Be ($replicaInstances.Count - 1)
            $missing[0].EmailAddress | Should -BeNullOrEmpty
        }

        It "Reports email drift for an operator that exists on every replica" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            # Present on every replica, so the missing-name arm cannot fire. What makes these rows
            # surface is the second arm: more than one distinct email address across the replicas.
            $script:operatorFixtureReplicas = $replicaInstances
            $driftIndex = 0
            foreach ($fixtureReplica in $replicaInstances) {
                $splatNewOperator = @{
                    SqlInstance     = $fixtureReplica
                    Operator        = $driftOperator
                    EmailAddress    = "drift$driftIndex@dbatools.io"
                    EnableException = $true
                }
                $null = New-DbaAgentOperator @splatNewOperator
                $driftIndex++
            }

            $rows = @(Compare-DbaAgReplicaOperator -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)
            $probeRows = @($rows | Where-Object OperatorName -eq $driftOperator)

            $probeRows.Count | Should -Be $replicaInstances.Count
            @($probeRows | Where-Object Status -eq "Missing").Count | Should -Be 0
            @($probeRows.EmailAddress | Select-Object -Unique).Count | Should -Be $replicaInstances.Count
        }

        It "Emits nothing for an operator that is identical on every replica" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            # The negative control for the leg above: same name, same email everywhere. Neither arm
            # of the emission predicate fires, so the operator must not appear in the output at all.
            $script:operatorFixtureReplicas = $replicaInstances
            foreach ($fixtureReplica in $replicaInstances) {
                $splatNewOperator = @{
                    SqlInstance     = $fixtureReplica
                    Operator        = $matchedOperator
                    EmailAddress    = "matched@dbatools.io"
                    EnableException = $true
                }
                $null = New-DbaAgentOperator @splatNewOperator
            }

            $rows = @(Compare-DbaAgReplicaOperator -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)
            @($rows | Where-Object OperatorName -eq $matchedOperator).Count | Should -Be 0
        }
    }
}

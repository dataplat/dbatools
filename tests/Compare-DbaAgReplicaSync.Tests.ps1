#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAgReplicaSync",
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
                "Exclude",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # This block covers the pre-comparison guard: the command connects and, before any comparison,
    # warns and returns nothing when the instance is not HADR-enabled, or when no Availability Group
    # matches the requested name. The aggregate comparison itself is covered by the live
    # multi-replica block further down.
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
            $result = @(Compare-DbaAgReplicaSync @splatCompare)
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
    LIVE MULTI-REPLICA COVERAGE. This command is the aggregate comparer: one pass over a >=2-replica
    Availability Group emitting rows for logins, agent jobs, credentials, linked servers, operators,
    alerts, proxies and custom errors, each family individually suppressible with -Exclude. Only the
    login family carries a "Different" status with a populated PropertyDifferences string; every
    other family reports presence alone. The legs below pin all three of those facts.

    The suite DISCOVERS the AG on a reachable HADR instance and skips-with-reason if none is
    provisioned. It never fails over or mutates the AG topology; the fixture it creates is a
    disposable dbatoolsci_ login placed on every replica and disabled on one, torn down by exact
    name.
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
        $driftLoginName = "dbatoolsci_agsyncdrift_$(Get-Random)"
        $script:driftLoginReplicas = @()

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
        foreach ($fixtureReplica in $script:driftLoginReplicas) {
            $splatRemoveLogin = @{
                SqlInstance   = $fixtureReplica
                Login         = $driftLoginName
                Confirm       = $false
                ErrorAction   = "SilentlyContinue"
                WarningAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveLogin
        }
    }

    Context "Against a multi-replica availability group" {
        It "Runs against a live AG and every emitted row has the documented shape" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            # Read-only. Whatever the AG's current configuration drift happens to be, every row must
            # carry the documented columns, name one of the documented object families, and report a
            # status the command can actually produce.
            $expectedObjectTypes = @("Login", "AgentJob", "Credential", "LinkedServer", "AgentOperator", "AgentAlert", "AgentProxy", "CustomError")
            $rows = @(Compare-DbaAgReplicaSync -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)
            $rows.Count | Should -BeGreaterThan 0
            foreach ($row in $rows) {
                $row.PSObject.Properties.Name | Should -Contain "AvailabilityGroup"
                $row.PSObject.Properties.Name | Should -Contain "Replica"
                $row.PSObject.Properties.Name | Should -Contain "ObjectType"
                $row.PSObject.Properties.Name | Should -Contain "ObjectName"
                $row.PSObject.Properties.Name | Should -Contain "Status"
                $row.AvailabilityGroup | Should -Be $resolvedAg
                $row.ObjectType | Should -BeIn $expectedObjectTypes
                $row.Status | Should -BeIn @("Missing", "Different")
            }
        }

        It "Reports a login that differs only in configuration as Different, with the property named" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            # Place the login on EVERY replica so the missing-name path cannot fire, then disable it
            # on one. The login family is the only one that compares properties rather than mere
            # presence, so this is the only way a Different row with a populated PropertyDifferences
            # can be produced. Record the teardown targets before creating anything.
            $script:driftLoginReplicas = $replicaInstances
            $driftSecret = ConvertTo-SecureString -String "dbatools.IO!$(Get-Random)" -AsPlainText -Force
            foreach ($fixtureReplica in $replicaInstances) {
                $splatNewLogin = @{
                    SqlInstance     = $fixtureReplica
                    Login           = $driftLoginName
                    SecurePassword  = $driftSecret
                    EnableException = $true
                }
                $null = New-DbaLogin @splatNewLogin
            }
            $null = Set-DbaLogin -SqlInstance $replicaInstances[0] -Login $driftLoginName -Disable -EnableException

            $rows = @(Compare-DbaAgReplicaSync -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -WarningAction SilentlyContinue)
            $probeRows = @($rows | Where-Object { $PSItem.ObjectType -eq "Login" -and $PSItem.ObjectName -eq $driftLoginName })

            # The comparison is against whichever replica the command picked as its baseline, so the
            # Different row lands on the disabled replica or on the others depending on that pick.
            # Either way the drift is reported, and it names IsDisabled as the differing property.
            $differentRows = @($probeRows | Where-Object Status -eq "Different")
            $differentRows.Count | Should -BeGreaterThan 0
            @($probeRows | Where-Object Status -eq "Missing").Count | Should -Be 0
            $differentRows[0].PropertyDifferences | Should -Match "IsDisabled"
        }

        It "Drops a whole object family from the comparison under -Exclude" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            # -Exclude gates each family's entire collection pass, so excluding Logins must remove
            # every Login row - including the drift fixture from the previous leg - while leaving the
            # other families untouched.
            $rows = @(Compare-DbaAgReplicaSync -SqlInstance $agInstance -AvailabilityGroup $resolvedAg -Exclude Logins -WarningAction SilentlyContinue)
            @($rows | Where-Object ObjectType -eq "Login").Count | Should -Be 0
            @($rows | Where-Object ObjectType -ne "Login").Count | Should -BeGreaterThan 0
        }
    }
}

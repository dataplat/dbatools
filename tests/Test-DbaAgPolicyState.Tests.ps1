#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Test-DbaAgPolicyState",
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
                "Secondary",
                "SecondarySqlCredential",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Always On predefined policy coverage" {
            BeforeAll {
                function New-MockAvailabilityReplica {
                    param(
                        [string]$Name,
                        [string]$Role,
                        [string]$ConnectionState,
                        [string]$JoinState,
                        [string]$AvailabilityMode,
                        [string]$UniqueId
                    )

                    $replica = New-Object -TypeName Microsoft.SqlServer.Management.Smo.AvailabilityReplica
                    $replica.Name = $Name
                    $replica | Add-Member -Force -MemberType ScriptProperty -Name Role -Value { $this.psobject.Properties["MockRole"].Value }
                    $replica | Add-Member -Force -MemberType ScriptProperty -Name ConnectionState -Value { $this.psobject.Properties["MockConnectionState"].Value }
                    $replica | Add-Member -Force -MemberType ScriptProperty -Name JoinState -Value { $this.psobject.Properties["MockJoinState"].Value }
                    $replica | Add-Member -Force -MemberType ScriptProperty -Name AvailabilityMode -Value { $this.psobject.Properties["MockAvailabilityMode"].Value }
                    $replica | Add-Member -Force -MemberType ScriptProperty -Name UniqueId -Value { $this.psobject.Properties["MockUniqueId"].Value }
                    $replica | Add-Member -Force -NotePropertyName MockRole -NotePropertyValue $Role
                    $replica | Add-Member -Force -NotePropertyName MockConnectionState -NotePropertyValue $ConnectionState
                    $replica | Add-Member -Force -NotePropertyName MockJoinState -NotePropertyValue $JoinState
                    $replica | Add-Member -Force -NotePropertyName MockAvailabilityMode -NotePropertyValue $AvailabilityMode
                    $replica | Add-Member -Force -NotePropertyName MockUniqueId -NotePropertyValue $UniqueId
                    $replica
                }

                function New-MockAvailabilityGroup {
                    $server = [PSCustomObject]@{
                        ClusterQuorumState = "NormalQuorum"
                    }

                    $primaryReplica = New-MockAvailabilityReplica -Name "PrimaryReplica" -Role "Primary" -ConnectionState "Connected" -JoinState "JoinedStandaloneInstance" -AvailabilityMode "SynchronousCommit" -UniqueId "primary-id"
                    $syncReplica = New-MockAvailabilityReplica -Name "SyncReplica" -Role "Secondary" -ConnectionState "Connected" -JoinState "JoinedStandaloneInstance" -AvailabilityMode "SynchronousCommit" -UniqueId "sync-id"

                    $databaseReplicaStates = @(
                        [PSCustomObject]@{
                            AvailabilityReplicaId         = "primary-id"
                            AvailabilityReplicaServerName = "PrimaryReplica"
                            AvailabilityDatabaseName      = "AgDb"
                            SynchronizationState          = "Synchronized"
                            ReplicaAvailabilityMode       = "SynchronousCommit"
                            IsSuspended                   = $false
                            IsJoined                      = $true
                        },
                        [PSCustomObject]@{
                            AvailabilityReplicaId         = "sync-id"
                            AvailabilityReplicaServerName = "SyncReplica"
                            AvailabilityDatabaseName      = "AgDb"
                            SynchronizationState          = "Synchronizing"
                            ReplicaAvailabilityMode       = "SynchronousCommit"
                            IsSuspended                   = $false
                            IsJoined                      = $true
                        }
                    )

                    $availabilityGroup = New-Object -TypeName Microsoft.SqlServer.Management.Smo.AvailabilityGroup
                    $availabilityGroup.Name = "AgOne"
                    $availabilityGroup | Add-Member -Force -MemberType ScriptMethod -Name Refresh -Value { }
                    $availabilityGroup | Add-Member -Force -MemberType ScriptProperty -Name ComputerName -Value { "sqlhost" }
                    $availabilityGroup | Add-Member -Force -MemberType ScriptProperty -Name InstanceName -Value { "MSSQLSERVER" }
                    $availabilityGroup | Add-Member -Force -MemberType ScriptProperty -Name SqlInstance -Value { "sqlhost" }
                    $availabilityGroup | Add-Member -Force -MemberType ScriptProperty -Name Parent -Value { $this.psobject.Properties["MockParent"].Value }
                    $availabilityGroup | Add-Member -Force -MemberType ScriptProperty -Name AvailabilityReplicas -Value { $this.psobject.Properties["MockAvailabilityReplicas"].Value }
                    $availabilityGroup | Add-Member -Force -MemberType ScriptProperty -Name DatabaseReplicaStates -Value { $this.psobject.Properties["MockDatabaseReplicaStates"].Value }
                    $availabilityGroup | Add-Member -Force -NotePropertyName MockParent -NotePropertyValue $server
                    $availabilityGroup | Add-Member -Force -NotePropertyName MockAvailabilityReplicas -NotePropertyValue @($primaryReplica, $syncReplica)
                    $availabilityGroup | Add-Member -Force -NotePropertyName MockDatabaseReplicaStates -NotePropertyValue $databaseReplicaStates
                    $availabilityGroup
                }

                $script:mockAvailabilityGroup = New-MockAvailabilityGroup

                Mock Get-DbaAvailabilityGroup { $script:mockAvailabilityGroup }
                Mock New-Object {
                    [PSCustomObject]@{
                        IsOnline                              = $true
                        IsAutoFailover                        = $true
                        NumberOfSynchronizedSecondaryReplicas = 1
                        NumberOfDisconnectedReplicas          = 0
                        NumberOfNotSynchronizingReplicas      = 0
                        NumberOfReplicasWithUnhealthyRole     = 0
                        NumberOfNotSynchronizedReplicas       = 0
                    }
                } -ParameterFilter {
                    $TypeName -eq "Microsoft.SqlServer.Management.Smo.AvailabilityGroupState"
                }
            }

            It "returns every documented policy with the expected categories" {
                $results = Test-DbaAgPolicyState -SqlInstance "sqlhost"

                $results.Count | Should -Be 21
                ($results | Where-Object PolicyName -eq "Availability Replica Data Synchronization State").Count | Should -Be 2
                ($results | Where-Object PolicyName -eq "Availability Replica Role State" | Select-Object -ExpandProperty Category -Unique) | Should -Be "Critical"
                ($results | Where-Object PolicyName -eq "Availability Replica Connection State" | Select-Object -ExpandProperty Category -Unique) | Should -Be "Critical"
                ($results | Where-Object PolicyName -eq "Availability Database Data Synchronization State" | Select-Object -ExpandProperty Category -Unique) | Should -Be "Warning"
            }

            It "marks synchronous replica synchronization lag as unhealthy at replica and database scope" {
                $results = Test-DbaAgPolicyState -SqlInstance "sqlhost"

                $replicaPolicy = $results | Where-Object { $PSItem.PolicyName -eq "Availability Replica Data Synchronization State" -and $PSItem.Replica -eq "SyncReplica" }
                $databasePolicy = $results | Where-Object { $PSItem.PolicyName -eq "Availability Database Data Synchronization State" -and $PSItem.Replica -eq "SyncReplica" -and $PSItem.Database -eq "AgDb" }

                $replicaPolicy.IsHealthy | Should -BeFalse
                $replicaPolicy.Issue | Should -Be "Data synchronization state of some availability database is not healthy."
                $databasePolicy.IsHealthy | Should -BeFalse
                $databasePolicy.Issue | Should -Be "Data synchronization state of availability database is not healthy."
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: the policy evaluation logic is already pinned by the mocked UnitTests
    # above; the live policy state across real replicas requires a multi-replica Availability
    # Group, which the standalone InstanceSingle does not provide - that leg is DEFERRED-TO-AG01
    # per the coordinator AG policy. What IS characterizable on a standalone instance is the guard
    # ahead of any evaluation: the no-input guard (connection-independent), and the resolution leg
    # through the compiled Get-DbaAvailabilityGroup, which on a non-HADR instance warns once and
    # yields nothing while an HADR instance filters a non-matching name silently. This command is
    # read-only ([CmdletBinding()] with no SupportsShouldProcess), so no WhatIf is passed.
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $isHadrEnabled = $server.IsHadrEnabled
        $instanceToken = "$([DbaInstanceParameter]$TestConfig.InstanceSingle)"
        $random = Get-Random
    }

    Context "Guarding before the evaluation" {
        It "Warns once and returns nothing when neither SqlInstance nor InputObject is supplied" {
            $splatNoInput = @{
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = @(Test-DbaAgPolicyState @splatNoInput)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must supply either -SqlInstance or an Input Object"
        }

        It "Evaluates nothing when the requested Availability Group does not exist" {
            $splatAbsentAg = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = "dbatoolsci_noag_$random"
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
            }
            $result = @(Test-DbaAgPolicyState @splatAbsentAg)
            $result.Count | Should -Be 0

            if ($isHadrEnabled) {
                # an HADR instance filters the absent name silently in Get-DbaAvailabilityGroup
                $warn.Count | Should -Be 0
            } else {
                # a non-HADR instance warns exactly once from the nested Get-DbaAvailabilityGroup
                $warn.Count | Should -Be 1
                $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
                $payload | Should -Be "Availability Group (HADR) is not configured for the instance: $instanceToken."
            }
        }
    }

    # The live evaluation leg. The mocked UnitTests above pin the policy logic in isolation;
    # these pin that it actually runs against real SMO. Assertions derive the expected shape
    # from the AG object rather than hardcoding the lab's current size, so they hold on any
    # Availability Group: the source emits 7 AG-level rows (Replica $null), then 4 rows per
    # AvailabilityReplica, then 3 rows per DatabaseReplicaState. IsHealthy is deliberately NOT
    # asserted to a value - real replica health is environmental, and a characterization test
    # that demands a green lab is a lab test, not a contract test.
    Context "Evaluating a real Availability Group" {
        BeforeAll {
            $liveAg = @(Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue)[0]
            $liveAgName = $liveAg.Name
            $expectedRowCount = 7 + (4 * @($liveAg.AvailabilityReplicas).Count) + (3 * @($liveAg.DatabaseReplicaStates).Count)

            $liveResult = @(Test-DbaAgPolicyState -SqlInstance $TestConfig.InstanceSingle -AvailabilityGroup $liveAgName -WarningAction SilentlyContinue)
        }

        It "Emits one row per policy per scoped object" {
            $liveResult.Count | Should -Be $expectedRowCount
        }

        It "Scopes every row to the requested Availability Group" {
            @($liveResult.AvailabilityGroup | Sort-Object -Unique) | Should -Be @($liveAgName)
        }

        It "Returns the documented property set on every row" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "AvailabilityGroup",
                "Replica",
                "Database",
                "PolicyName",
                "Category",
                "Facet",
                "IsHealthy",
                "Issue",
                "Details"
            )
            foreach ($row in $liveResult) {
                Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $row.PSObject.Properties.Name | Should -BeNullOrEmpty
            }
        }

        It "Emits the seven Availability-Group-level policies once each, unscoped to a replica" {
            $agLevelPolicies = @(
                "WSFC Cluster State",
                "Availability Group Online State",
                "Availability Group Automatic Failover Readiness",
                "Availability Replicas Connection State",
                "Availability Replicas Data Synchronization State",
                "Availability Replicas Role State",
                "Synchronous Replicas Data Synchronization State"
            )
            $agLevelRows = @($liveResult | Where-Object { $PSItem.PolicyName -in $agLevelPolicies })

            $agLevelRows.Count | Should -Be $agLevelPolicies.Count
            @($agLevelRows.Replica | Sort-Object -Unique) | Should -BeNullOrEmpty
        }

        It "Reports IsHealthy as a boolean on every row" {
            foreach ($row in $liveResult) {
                $row.IsHealthy | Should -BeOfType [bool]
            }
        }

        It "Accepts an Availability Group on the pipeline and evaluates the same policies" {
            $splatPipedAg = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = $liveAgName
                WarningAction     = "SilentlyContinue"
            }
            $pipedResult = @(Get-DbaAvailabilityGroup @splatPipedAg | Test-DbaAgPolicyState -WarningAction SilentlyContinue)

            $pipedResult.Count | Should -Be $liveResult.Count
            @($pipedResult.PolicyName | Sort-Object -Unique) | Should -Be @($liveResult.PolicyName | Sort-Object -Unique)
        }
    }
}
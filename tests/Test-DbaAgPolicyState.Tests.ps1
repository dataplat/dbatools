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
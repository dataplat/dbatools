function Compare-DbaAgReplicaOperator {
    <#
    .SYNOPSIS
        Compares SQL Agent Operators across Availability Group replicas to identify configuration differences.

    .DESCRIPTION
        Compares SQL Agent Operators across all replicas in an Availability Group to identify differences in operator configurations. This helps ensure consistency across AG replicas and detect when operators have been created or removed on one replica but not others.

        This is particularly useful for verifying that junior DBAs have applied alert notification changes to all replicas or for troubleshooting issues where operator configurations have drifted between replicas.

        Compares operator names and their email addresses to detect configuration drift.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Can be any replica in the Availability Group.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specifies one or more Availability Group names to compare operators across their replicas.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, AG, Operator, Agent
        Author: dbatools team

        Website: https://dbatools.io
        Copyright: (c) 2025 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Compare-DbaAgReplicaOperator

    .OUTPUTS
        PSCustomObject

        Returns one object per detected operator configuration difference across replicas. Objects are returned only when an operator configuration differs between replicas (either present on some replicas but missing on others, or present with different email addresses).

        Properties:
        - AvailabilityGroup: Name of the Availability Group being compared
        - Replica: The SQL Server instance name of the replica
        - OperatorName: Name of the SQL Agent operator
        - Status: Configuration status of the operator on this replica ("Present" or "Missing")
        - EmailAddress: Email address of the operator (null if Status is "Missing")

    .EXAMPLE
        PS C:\> Compare-DbaAgReplicaOperator -SqlInstance sql2016 -AvailabilityGroup AG1

        Compares all SQL Agent Operators across replicas in the AG1 Availability Group.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2016 | Compare-DbaAgReplicaOperator

        Compares SQL Agent Operators for all Availability Groups on sql2016 via pipeline input.
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Failure connecting to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (-not $server.IsHadrEnabled) {
                Stop-Function -Message "Availability Group (HADR) is not configured for the instance: $instance." -Target $instance -Continue
            }

            $availabilityGroups = $server.AvailabilityGroups

            if ($AvailabilityGroup) {
                $availabilityGroups = $availabilityGroups | Where-Object Name -in $AvailabilityGroup
            }

            if (-not $availabilityGroups) {
                Stop-Function -Message "No Availability Groups found on $instance matching the specified criteria." -Target $instance -Continue
            }

            foreach ($ag in $availabilityGroups) {
                $replicas = $ag.AvailabilityReplicas

                if ($replicas.Count -lt 2) {
                    Stop-Function -Message "Availability Group '$($ag.Name)' has less than 2 replicas. Nothing to compare." -Target $ag -Continue
                }

                $replicaInstances = @()
                foreach ($replica in $replicas) {
                    $replicaInstances += $replica.Name
                }

                $operatorsByReplica = @{}
                $allOperatorNames = New-Object System.Collections.ArrayList

                foreach ($replicaInstance in $replicaInstances) {
                    try {
                        $splatConnection = @{
                            SqlInstance   = $replicaInstance
                            SqlCredential = $SqlCredential
                        }
                        $replicaServer = Connect-DbaInstance @splatConnection

                        $operators = Get-DbaAgentOperator -SqlInstance $replicaServer

                        $operatorsByReplica[$replicaInstance] = $operators

                        foreach ($operator in $operators) {
                            if ($operator.Name -notin $allOperatorNames) {
                                $null = $allOperatorNames.Add($operator.Name)
                            }
                        }
                    } catch {
                        Stop-Function -Message "Failed to retrieve operators from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue
                    }
                }

                foreach ($operatorName in $allOperatorNames) {
                    $differences = New-Object System.Collections.ArrayList

                    foreach ($replicaInstance in $replicaInstances) {
                        $operator = $operatorsByReplica[$replicaInstance] | Where-Object Name -eq $operatorName

                        if (-not $operator) {
                            $null = $differences.Add([PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    OperatorName      = $operatorName
                                    Status            = "Missing"
                                    EmailAddress      = $null
                                })
                        } else {
                            $null = $differences.Add([PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    OperatorName      = $operatorName
                                    Status            = "Present"
                                    EmailAddress      = $operator.EmailAddress
                                })
                        }
                    }

                    if ($differences.Count -gt 0) {
                        $hasMissing = $differences | Where-Object Status -eq "Missing"
                        $emails = $differences | Where-Object Status -eq "Present" | Select-Object -ExpandProperty EmailAddress
                        $uniqueEmails = $emails | Select-Object -Unique

                        if ($hasMissing -or $uniqueEmails.Count -gt 1) {
                            foreach ($diff in $differences) {
                                $diff
                            }
                        }
                    }
                }
            }
        }
    }
}

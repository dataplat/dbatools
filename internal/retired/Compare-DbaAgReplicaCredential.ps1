function Compare-DbaAgReplicaCredential {
    <#
    .SYNOPSIS
        Compares SQL Server Credentials across Availability Group replicas to identify configuration differences.

    .DESCRIPTION
        Compares SQL Server Credentials across all replicas in an Availability Group to identify differences in credential configurations. This helps ensure consistency across AG replicas and detect when credentials have been created or removed on one replica but not others.

        This is particularly useful for verifying that junior DBAs have applied security changes to all replicas or for troubleshooting issues where credential configurations have drifted between replicas.

        Compares credential names and their associated identities to detect configuration drift.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Can be any replica in the Availability Group.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specifies one or more Availability Group names to compare credentials across their replicas.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, AG, Credential, Security
        Author: dbatools team

        Website: https://dbatools.io
        Copyright: (c) 2025 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Compare-DbaAgReplicaCredential

    .OUTPUTS
        PSCustomObject

        Returns one object per credential that has configuration differences across replicas in the Availability Group.

        Properties:
        - AvailabilityGroup: The name of the Availability Group being compared
        - Replica: The name of the replica instance where the credential status was checked
        - CredentialName: The name of the SQL Server credential
        - Status: The credential state on this replica ("Present" if the credential exists, "Missing" if it doesn't)
        - Identity: The credential's identity/principal on replicas where the credential is Present; $null where Status is "Missing"

        Only credentials with differences (missing on at least one replica or having different identities across replicas) are returned.

    .EXAMPLE
        PS C:\> Compare-DbaAgReplicaCredential -SqlInstance sql2016 -AvailabilityGroup AG1

        Compares all SQL Server Credentials across replicas in the AG1 Availability Group.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2016 | Compare-DbaAgReplicaCredential

        Compares SQL Server Credentials for all Availability Groups on sql2016 via pipeline input.
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

                $credentialsByReplica = @{}
                $allCredentialNames = New-Object System.Collections.ArrayList

                foreach ($replicaInstance in $replicaInstances) {
                    try {
                        $splatConnection = @{
                            SqlInstance   = $replicaInstance
                            SqlCredential = $SqlCredential
                        }
                        $replicaServer = Connect-DbaInstance @splatConnection

                        $credentials = Get-DbaCredential -SqlInstance $replicaServer

                        $credentialsByReplica[$replicaInstance] = $credentials

                        foreach ($credential in $credentials) {
                            if ($credential.Name -notin $allCredentialNames) {
                                $null = $allCredentialNames.Add($credential.Name)
                            }
                        }
                    } catch {
                        Stop-Function -Message "Failed to retrieve credentials from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue
                    }
                }

                foreach ($credentialName in $allCredentialNames) {
                    $differences = New-Object System.Collections.ArrayList

                    foreach ($replicaInstance in $replicaInstances) {
                        $credential = $credentialsByReplica[$replicaInstance] | Where-Object Name -eq $credentialName

                        if (-not $credential) {
                            $null = $differences.Add([PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    CredentialName    = $credentialName
                                    Status            = "Missing"
                                    Identity          = $null
                                })
                        } else {
                            $null = $differences.Add([PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    CredentialName    = $credentialName
                                    Status            = "Present"
                                    Identity          = $credential.Identity
                                })
                        }
                    }

                    if ($differences.Count -gt 0) {
                        $hasMissing = $differences | Where-Object Status -eq "Missing"
                        $identities = $differences | Where-Object Status -eq "Present" | Select-Object -ExpandProperty Identity
                        $uniqueIdentities = $identities | Select-Object -Unique

                        if ($hasMissing -or $uniqueIdentities.Count -gt 1) {
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

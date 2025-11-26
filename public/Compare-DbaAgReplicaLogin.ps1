function Compare-DbaAgReplicaLogin {
    <#
    .SYNOPSIS
        Compares SQL Server logins across Availability Group replicas to identify configuration differences.

    .DESCRIPTION
        Compares SQL Server logins across all replicas in an Availability Group to identify differences in login configurations. This helps ensure consistency across AG replicas and detect when logins have been created, modified, or removed on one replica but not others.

        This is particularly useful for verifying that junior DBAs have applied security changes to all replicas or for troubleshooting access issues where login configurations have drifted between replicas.

        By default, compares login names and their presence/absence. Use -IncludeModifiedDate to also compare modify_date timestamps from sys.server_principals to detect configuration drift.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Can be any replica in the Availability Group.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specifies one or more Availability Group names to compare logins across their replicas.

    .PARAMETER ExcludeSystemLogin
        Excludes built-in system logins from the comparison results.
        Use this to focus on user-created logins and ignore built-in SQL Server logins.

    .PARAMETER IncludeModifiedDate
        Includes modify_date comparison in addition to login name comparison.
        Use this to detect when logins have been reconfigured on some replicas but not others.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, AG, Login, Security
        Author: dbatools team

        Website: https://dbatools.io
        Copyright: (c) 2025 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Compare-DbaAgReplicaLogin

    .EXAMPLE
        PS C:\> Compare-DbaAgReplicaLogin -SqlInstance sql2016 -AvailabilityGroup AG1

        Compares all SQL Server logins across replicas in the AG1 Availability Group.

    .EXAMPLE
        PS C:\> Compare-DbaAgReplicaLogin -SqlInstance sql2016 -AvailabilityGroup AG1 -ExcludeSystemLogin

        Compares user-created SQL Server logins across replicas, excluding system logins.

    .EXAMPLE
        PS C:\> Compare-DbaAgReplicaLogin -SqlInstance sql2016 -AvailabilityGroup AG1 -IncludeModifiedDate

        Compares SQL Server logins including their modify_date property to detect configuration drift.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2016 | Compare-DbaAgReplicaLogin

        Compares SQL Server logins for all Availability Groups on sql2016 via pipeline input.
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [switch]$ExcludeSystemLogin,
        [switch]$IncludeModifiedDate,
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

                $loginsByReplica = @{}
                $allLoginNames = New-Object System.Collections.ArrayList

                foreach ($replicaInstance in $replicaInstances) {
                    try {
                        $splatConnection = @{
                            SqlInstance   = $replicaInstance
                            SqlCredential = $SqlCredential
                        }
                        $replicaServer = Connect-DbaInstance @splatConnection

                        if ($ExcludeSystemLogin) {
                            $logins = Get-DbaLogin -SqlInstance $replicaServer -ExcludeSystemLogin
                        } else {
                            $logins = Get-DbaLogin -SqlInstance $replicaServer
                        }

                        if ($IncludeModifiedDate) {
                            $query = "SELECT name, modify_date FROM sys.server_principals WHERE [type] IN ('S', 'U', 'G')"
                            $modifyDates = Invoke-DbaQuery -SqlInstance $replicaServer -Query $query -As PSObject

                            $loginDetails = New-Object System.Collections.ArrayList
                            foreach ($login in $logins) {
                                $modifyDate = ($modifyDates | Where-Object name -eq $login.Name).modify_date
                                $null = $loginDetails.Add([PSCustomObject]@{
                                        Name        = $login.Name
                                        ModifyDate  = $modifyDate
                                        CreateDate  = $login.CreateDate
                                        LoginType   = $login.LoginType
                                    })
                            }
                            $loginsByReplica[$replicaInstance] = $loginDetails
                        } else {
                            $loginsByReplica[$replicaInstance] = $logins
                        }

                        foreach ($login in $logins) {
                            if ($login.Name -notin $allLoginNames) {
                                $null = $allLoginNames.Add($login.Name)
                            }
                        }
                    } catch {
                        Stop-Function -Message "Failed to retrieve logins from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue
                    }
                }

                foreach ($loginName in $allLoginNames) {
                    $differences = New-Object System.Collections.ArrayList

                    foreach ($replicaInstance in $replicaInstances) {
                        $login = $loginsByReplica[$replicaInstance] | Where-Object Name -eq $loginName

                        if (-not $login) {
                            $null = $differences.Add([PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    LoginName         = $loginName
                                    Status            = "Missing"
                                    ModifyDate        = $null
                                    CreateDate        = $null
                                })
                        } elseif ($IncludeModifiedDate) {
                            $null = $differences.Add([PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    LoginName         = $loginName
                                    Status            = "Present"
                                    ModifyDate        = $login.ModifyDate
                                    CreateDate        = $login.CreateDate
                                })
                        }
                    }

                    if ($differences.Count -gt 0) {
                        $hasMissing = $differences | Where-Object Status -eq "Missing"

                        if ($hasMissing -or $IncludeModifiedDate) {
                            if ($IncludeModifiedDate) {
                                $dates = $differences | Where-Object Status -eq "Present" | Select-Object -ExpandProperty ModifyDate
                                $uniqueDates = $dates | Select-Object -Unique

                                if ($uniqueDates.Count -gt 1 -or $hasMissing) {
                                    foreach ($diff in $differences) {
                                        $diff
                                    }
                                }
                            } else {
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
}

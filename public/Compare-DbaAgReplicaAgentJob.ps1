function Compare-DbaAgReplicaAgentJob {
    <#
    .SYNOPSIS
        Compares SQL Agent Jobs across Availability Group replicas to identify configuration differences.

    .DESCRIPTION
        Compares SQL Agent Jobs across all replicas in an Availability Group to identify differences in job configurations. This helps ensure consistency across AG replicas and detect when jobs have been modified on one replica but not others.

        This is particularly useful for verifying that junior DBAs have applied changes to all replicas or for troubleshooting issues where job configurations have drifted between replicas.

        By default, compares job names and their presence/absence. Use -IncludeModifiedDate to also compare DateLastModified timestamps to detect configuration drift.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Can be any replica in the Availability Group.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specifies one or more Availability Group names to compare jobs across their replicas.

    .PARAMETER ExcludeSystemJob
        Excludes system jobs from the comparison results.
        Use this to focus on user-created jobs and ignore built-in SQL Server jobs.

    .PARAMETER IncludeModifiedDate
        Includes DateLastModified comparison in addition to job name comparison.
        Use this to detect when jobs have been reconfigured on some replicas but not others.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, AG, Job, Agent
        Author: dbatools team

        Website: https://dbatools.io
        Copyright: (c) 2025 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Compare-DbaAgReplicaAgentJob

    .EXAMPLE
        PS C:\> Compare-DbaAgReplicaAgentJob -SqlInstance sql2016 -AvailabilityGroup AG1

        Compares all SQL Agent Jobs across replicas in the AG1 Availability Group.

    .EXAMPLE
        PS C:\> Compare-DbaAgReplicaAgentJob -SqlInstance sql2016 -AvailabilityGroup AG1 -ExcludeSystemJob

        Compares user-created SQL Agent Jobs across replicas, excluding system jobs.

    .EXAMPLE
        PS C:\> Compare-DbaAgReplicaAgentJob -SqlInstance sql2016 -AvailabilityGroup AG1 -IncludeModifiedDate

        Compares SQL Agent Jobs including their DateLastModified property to detect configuration drift.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2016 | Compare-DbaAgReplicaAgentJob

        Compares SQL Agent Jobs for all Availability Groups on sql2016 via pipeline input.
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [switch]$ExcludeSystemJob,
        [switch]$IncludeModifiedDate,
        [switch]$EnableException
    )

    begin {
        $systemJobs = @(
            "syspolicy_purge_history",
            "DBA_AgentJobHistoryRetention",
            "DBA_IndexOptimize",
            "DBA_CommandLogCleanup"
        )
    }

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

                $jobsByReplica = @{}
                $allJobNames = New-Object System.Collections.ArrayList

                foreach ($replicaInstance in $replicaInstances) {
                    try {
                        $splatConnection = @{
                            SqlInstance     = $replicaInstance
                            SqlCredential   = $SqlCredential
                            EnableException = $true
                        }
                        $replicaServer = Connect-DbaInstance @splatConnection

                        $jobs = Get-DbaAgentJob -SqlInstance $replicaServer

                        if ($ExcludeSystemJob) {
                            $jobs = $jobs | Where-Object Name -notin $systemJobs
                        }

                        $jobsByReplica[$replicaInstance] = $jobs

                        foreach ($job in $jobs) {
                            if ($job.Name -notin $allJobNames) {
                                $null = $allJobNames.Add($job.Name)
                            }
                        }
                    } catch {
                        Stop-Function -Message "Failed to retrieve jobs from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue
                    }
                }

                $primaryReplica = $replicaInstances[0]

                foreach ($jobName in $allJobNames) {
                    $differences = New-Object System.Collections.ArrayList

                    foreach ($replicaInstance in $replicaInstances) {
                        $job = $jobsByReplica[$replicaInstance] | Where-Object Name -eq $jobName

                        if (-not $job) {
                            $null = $differences.Add([PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    JobName           = $jobName
                                    Status            = "Missing"
                                    DateLastModified  = $null
                                })
                        } elseif ($IncludeModifiedDate) {
                            $null = $differences.Add([PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    JobName           = $jobName
                                    Status            = "Present"
                                    DateLastModified  = $job.DateLastModified
                                })
                        }
                    }

                    if ($differences.Count -gt 0) {
                        $hasMissing = $differences | Where-Object Status -eq "Missing"

                        if ($hasMissing -or $IncludeModifiedDate) {
                            if ($IncludeModifiedDate) {
                                $dates = $differences | Where-Object Status -eq "Present" | Select-Object -ExpandProperty DateLastModified
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

function Sync-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Synchronizes server-level objects from primary to secondary replicas in availability groups

    .DESCRIPTION
        Copies server-level objects from the primary replica to all secondary replicas in an availability group. Availability groups only synchronize databases, not the server-level dependencies that applications need to function properly after failover.

        This command ensures that logins, SQL Agent jobs, linked servers, and other critical server objects exist on all replicas so your applications work seamlessly regardless of which replica becomes primary. By default, it synchronizes these object types:

        SpConfigure
        CustomErrors
        Credentials
        DatabaseMail
        LinkedServers
        Logins
        LoginPermissions
        SystemTriggers
        DatabaseOwner
        AgentCategory
        AgentOperator
        AgentAlert
        AgentProxy
        AgentSchedule
        AgentJob

        Any of these object types can be excluded using the -Exclude parameter. For granular control over specific objects (like excluding individual jobs or logins), use the -ExcludeJob, -ExcludeLogin parameters or the underlying Copy-Dba* commands directly.

        The command copies ALL objects of each enabled type - it doesn't filter based on which objects are actually used by the availability group databases. Use the exclusion parameters to limit scope when needed.

    .PARAMETER Primary
        The primary replica SQL Server instance for the availability group. This is the source server from which all server-level objects will be copied.
        Required when not using InputObject parameter. Server version must be SQL Server 2012 or higher.

    .PARAMETER PrimarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Secondary
        The secondary replica SQL Server instances where server-level objects will be copied to. Can specify multiple instances.
        If not specified, the function will automatically discover all secondary replicas in the availability group. Server version must be SQL Server 2012 or higher.

    .PARAMETER SecondarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        The name of the specific availability group to synchronize server objects for.
        When specified, the function will identify all replicas in this AG and sync objects from primary to all secondaries.

    .PARAMETER Exclude
        Excludes specific object types from being synchronized to avoid conflicts or reduce sync time.
        Useful when you need to manually manage certain objects or when some object types cause issues in your environment. Valid values:

        SpConfigure, CustomErrors, Credentials, DatabaseMail, LinkedServers, Logins, LoginPermissions,
        SystemTriggers, DatabaseOwner, AgentCategory, AgentOperator, AgentAlert, AgentProxy, AgentSchedule, AgentJob

    .PARAMETER Login
        Specifies which login accounts to synchronize to secondary replicas. Accepts an array of login names.
        Use this when you only need to sync specific service accounts or application logins rather than all logins on the server.

    .PARAMETER ExcludeLogin
        Specifies login accounts to skip during synchronization. Accepts an array of login names.
        Commonly used to exclude system accounts, sa, or logins that should remain unique per replica for monitoring or maintenance purposes.

    .PARAMETER Job
        Specifies which SQL Agent jobs to synchronize to secondary replicas. Accepts an array of job names.
        Use this when you only need to sync critical jobs like backup jobs or maintenance tasks rather than all jobs on the server.

    .PARAMETER ExcludeJob
        Specifies SQL Agent jobs to skip during synchronization. Accepts an array of job names.
        Commonly used to exclude replica-specific jobs like log shipping, local backups, or jobs that should only run on the primary replica.

    .PARAMETER DisableJobOnDestination
        Disables all synchronized jobs on secondary replicas after copying them from the primary.
        Use this when jobs should only run on the primary replica or when you need to manually control which jobs run on each replica after failover.

    .PARAMETER InputObject
        Accepts availability group objects from Get-DbaAvailabilityGroup for pipeline processing.
        Use this to sync multiple availability groups at once or to process specific AGs returned by filtering commands.

    .PARAMETER Force
        Drops and recreates existing objects on secondary replicas instead of skipping them.
        Use this when you need to update objects that already exist on secondaries or when objects have configuration differences that need to be synchronized.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AG, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Sync-DbaAvailabilityGroup

    .EXAMPLE
        PS C:\> Sync-DbaAvailabilityGroup -Primary sql2016a -AvailabilityGroup db3

        Syncs the following on all replicas found in the db3 AG:
        SpConfigure, CustomErrors, Credentials, DatabaseMail, LinkedServers
        Logins, LoginPermissions, SystemTriggers, DatabaseOwner, AgentCategory,
        AgentOperator, AgentAlert, AgentProxy, AgentSchedule, AgentJob

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2016a | Sync-DbaAvailabilityGroup -ExcludeType LoginPermissions, LinkedServers -ExcludeLogin login1, login2 -Job job1, job2

        Syncs the following on all replicas found in all AGs on the specified instance:
        SpConfigure, CustomErrors, Credentials, DatabaseMail, Logins,
        SystemTriggers, DatabaseOwner, AgentCategory, AgentOperator
        AgentAlert, AgentProxy, AgentSchedule, AgentJob.

        Copies all logins except for login1 and login2 and only syncs job1 and job2

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2016a | Sync-DbaAvailabilityGroup -WhatIf

        Shows what would happen if the command were to run but doesn't actually perform the action.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [DbaInstanceParameter]$Primary,
        [PSCredential]$PrimarySqlCredential,
        [DbaInstanceParameter[]]$Secondary,
        [PSCredential]$SecondarySqlCredential,
        [string]$AvailabilityGroup,
        [Alias("ExcludeType")]
        [ValidateSet('AgentCategory', 'AgentOperator', 'AgentAlert', 'AgentProxy', 'AgentSchedule', 'AgentJob', 'Credentials', 'CustomErrors', 'DatabaseMail', 'DatabaseOwner', 'LinkedServers', 'Logins', 'LoginPermissions', 'SpConfigure', 'SystemTriggers')]
        [string[]]$Exclude,
        [string[]]$Login,
        [string[]]$ExcludeLogin,
        [string[]]$Job,
        [string[]]$ExcludeJob,
        [switch]$DisableJobOnDestination,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $allcombos = @()
    }
    process {
        if (Test-Bound -Not Primary, InputObject) {
            Stop-Function -Message "You must supply either -Primary or an Input Object"
            return
        }

        if (-not $AvailabilityGroup -and -not $Secondary -and -not $InputObject) {
            Stop-Function -Message "You must specify a secondary or an availability group."
            return
        }

        if ($InputObject) {
            $server = $InputObject.Parent
        } else {
            try {
                $server = Connect-DbaInstance -SqlInstance $Primary -SqlCredential $PrimarySqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Primary
                return
            }
        }

        if ($AvailabilityGroup) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $AvailabilityGroup
        }

        if ($InputObject) {
            $Secondary += (($InputObject.AvailabilityReplicas | Where-Object Name -ne $server.DomainInstanceName).Name | Select-Object -Unique)
        }

        if ($Secondary) {
            $Secondary = $Secondary | Sort-Object
            $secondaries = @()
            foreach ($computer in $Secondary) {
                try {
                    $secondaries += Connect-DbaInstance -SqlInstance $computer -SqlCredential $SecondarySqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $computer -Continue
                }
            }
        }

        $thiscombo = [PSCustomObject]@{
            PrimaryServer   = $server
            SecondaryServer = $secondaries
        }

        # In the event that someone pipes in an availability group, this will keep the sync from running a bunch of times
        $dupe = $false

        foreach ($ag in $allcombos) {
            if ($ag.PrimaryServer.Name -eq $thiscombo.PrimaryServer.Name -and
                $ag.SecondaryServer.Name.ToString() -eq $thiscombo.SecondaryServer.Name.ToString()) {
                $dupe = $true
            }
        }

        if ($dupe -eq $false) {
            $allcombos += $thiscombo
        }
    }

    end {
        if (Test-FunctionInterrupt) { return }

        # now that all combinations have been figured out, begin sync without duplicating work
        foreach ($ag in $allcombos) {
            $server = $ag.PrimaryServer
            $secondaries = $ag.SecondaryServer

            $stepCounter = 0
            $activity = "Syncing availability group $AvailabilityGroup"

            if (-not $secondaries) {
                Stop-Function -Message "No secondaries found."
                return
            }

            $primaryserver = $server.Name
            $secondaryservers = $secondaries.Name -join ", "

            if ($Exclude -notcontains "SpConfigure") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing SQL Server Configuration"
                Copy-DbaSpConfigure -Source $server -Destination $secondaries
            }

            if ($Exclude -notcontains "Logins") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing logins"
                Copy-DbaLogin -Source $server -Destination $secondaries -Login $Login -ExcludeLogin $ExcludeLogin -Force:$Force
            }

            if ($Exclude -notcontains "DatabaseOwner") {
                if ($PSCmdlet.ShouldProcess("Updating database owners to match newly migrated logins from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Updating database owners to match newly migrated logins"
                    foreach ($sec in $secondaries) {
                        $null = Update-SqlDbOwner -Source $server -Destination $sec
                    }
                }
            }

            if ($Exclude -notcontains "CustomErrors") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing custom errors (user defined messages)"
                Copy-DbaCustomError -Source $server -Destination $secondaries -Force:$Force
            }

            if ($Exclude -notcontains "Credentials") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing SQL credentials"
                Copy-DbaCredential -Source $server -Destination $secondaries -Force:$Force
            }

            if ($Exclude -notcontains "DatabaseMail") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing database mail"
                Copy-DbaDbMail -Source $server -Destination $secondaries -Force:$Force
            }

            if ($Exclude -notcontains "LinkedServers") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing linked servers"
                Copy-DbaLinkedServer -Source $server -Destination $secondaries -Force:$Force
            }

            if ($Exclude -notcontains "SystemTriggers") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing System Triggers"
                Copy-DbaInstanceTrigger -Source $server -Destination $secondaries -Force:$Force
            }

            if ($Exclude -notcontains "AgentCategory") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Categories"
                Copy-DbaAgentJobCategory -Source $server -Destination $secondaries -Force:$force
                $secondaries.JobServer.JobCategories.Refresh()
                $secondaries.JobServer.OperatorCategories.Refresh()
                $secondaries.JobServer.AlertCategories.Refresh()
            }

            if ($Exclude -notcontains "AgentOperator") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Operators"
                Copy-DbaAgentOperator -Source $server -Destination $secondaries -Force:$force
                $secondaries.JobServer.Operators.Refresh()
            }

            if ($Exclude -notcontains "AgentAlert") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Alerts"
                Copy-DbaAgentAlert -Source $server -Destination $secondaries -Force:$force -IncludeDefaults
            }

            if ($Exclude -notcontains "AgentProxy") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Proxy Accounts"
                Copy-DbaAgentProxy -Source $server -Destination $secondaries -Force:$force
                $secondaries.JobServer.ProxyAccounts.Refresh()
            }

            if ($Exclude -notcontains "AgentSchedule") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Schedules"
                Copy-DbaAgentSchedule -Source $server -Destination $secondaries -Force:$force
                $secondaries.JobServer.SharedSchedules.Refresh()
                $secondaries.JobServer.Refresh()
                $secondaries.Refresh()
            }

            if ($Exclude -notcontains "AgentJob") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Jobs"
                Copy-DbaAgentJob -Source $server -Destination $secondaries -Force:$force -Job $Job -ExcludeJob $ExcludeJob -DisableOnDestination:$DisableJobOnDestination
            }

            if ($Exclude -notcontains "LoginPermissions") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing login permissions"
                Sync-DbaLoginPermission -Source $server -Destination $secondaries -Login $Login -ExcludeLogin $ExcludeLogin
            }
        }
    }
}
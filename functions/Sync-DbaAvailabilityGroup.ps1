function Sync-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Syncs dependent objects such as jobs, logins and custom errors for availability groups

    .DESCRIPTION
        Syncs dependent objects for availability groups. Such objects include:

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

        Note that any of these can be excluded. For specific object exclusions (such as a single job), using the underlying Copy-Dba* command will be required.

        This command does not filter by which logins are in use by the ag databases or which linked servers are used. All objects that are not excluded will be copied like hulk smash.

    .PARAMETER Primary
        The primary SQL Server instance. Server version must be SQL Server version 2012 or higher.

    .PARAMETER PrimarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Secondary
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SecondarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        The name of the Availability Group.

    .PARAMETER Exclude
        Exclude one or more objects to export

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

    .PARAMETER Login
        Specific logins to sync. If unspecified, all logins will be processed.

    .PARAMETER ExcludeLogin
        Specific logins to exclude when performing the sync. If unspecified, all logins will be processed.

    .PARAMETER Job
        Specific jobs to sync. If unspecified, all jobs will be processed.

    .PARAMETER ExcludeJob
        Specific jobs to exclude when performing the sync. If unspecified, all jobs will be processed.

    .PARAMETER InputObject
        Enables piping from Get-DbaAvailabilityGroup.

    .PARAMETER Force
        If this switch is enabled, the objects will dropped and recreated on Destination.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, HA, AG
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
        if (-not $AvailabilityGroup -and -not $Secondary -and -not $InputObject) {
            Stop-Function -Message "You must specify a secondary or an availability group."
            return
        }

        if ($InputObject) {
            $server = $InputObject.Parent
        } else {
            try {
                $server = Connect-SqlInstance -SqlInstance $Primary -SqlCredential $PrimarySqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $Primary" -Category ConnectionError -ErrorRecord $_ -Target $Primary
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
                    $secondaries += Connect-SqlInstance -SqlInstance $computer -SqlCredential $SecondarySqlCredential
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $computer" -Category ConnectionError -ErrorRecord $_ -Target $Primary
                    return
                }
            }
        }

        $thiscombo = [pscustomobject]@{
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
                if ($PSCmdlet.ShouldProcess("Syncing SQL Server Configuration from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing SQL Server Configuration"
                    Copy-DbaSpConfigure -Source $server -Destination $secondaries
                }
            }

            if ($Exclude -notcontains "Logins") {
                if ($PSCmdlet.ShouldProcess("Syncing logins from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing logins"
                    Copy-DbaLogin -Source $server -Destination $secondaries -Login $Login -ExcludeLogin $ExcludeLogin -Force:$Force
                }
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
                if ($PSCmdlet.ShouldProcess("Syncing custom errors (user defined messages) from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing custom errors (user defined messages)"
                    Copy-DbaCustomError -Source $server -Destination $secondaries -Force:$Force
                }
            }

            if ($Exclude -notcontains "Credentials") {
                if ($PSCmdlet.ShouldProcess("Syncing SQL credentials from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing SQL credentials"
                    Copy-DbaCredential -Source $server -Destination $secondaries -Force:$Force
                }
            }

            if ($Exclude -notcontains "DatabaseMail") {
                if ($PSCmdlet.ShouldProcess("Syncing database mail from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing database mail"
                    Copy-DbaDbMail -Source $server -Destination $secondaries -Force:$Force
                }
            }

            if ($Exclude -notcontains "LinkedServers") {
                if ($PSCmdlet.ShouldProcess("Syncing linked servers from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing linked servers"
                    Copy-DbaLinkedServer -Source $server -Destination $secondaries -Force:$Force
                }
            }

            if ($Exclude -notcontains "SystemTriggers") {
                if ($PSCmdlet.ShouldProcess("Syncing System Triggers from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing System Triggers"
                    Copy-DbaInstanceTrigger -Source $server -Destination $secondaries -Force:$Force
                }
            }

            if ($Exclude -notcontains "AgentCategory") {
                if ($PSCmdlet.ShouldProcess("Syncing Agent Categories from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Categories"
                    Copy-DbaAgentJobCategory -Source $server -Destination $secondaries -Force:$force
                    $secondaries.JobServer.JobCategories.Refresh()
                    $secondaries.JobServer.OperatorCategories.Refresh()
                    $secondaries.JobServer.AlertCategories.Refresh()
                }
            }

            if ($Exclude -notcontains "AgentOperator") {
                if ($PSCmdlet.ShouldProcess("Syncing Agent Operators from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Operators"
                    Copy-DbaAgentOperator -Source $server -Destination $secondaries -Force:$force
                    $secondaries.JobServer.Operators.Refresh()
                }
            }

            if ($Exclude -notcontains "AgentAlert") {
                if ($PSCmdlet.ShouldProcess("Syncing Agent Alerts from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Alerts"
                    Copy-DbaAgentAlert -Source $server -Destination $secondaries -Force:$force -IncludeDefaults
                    $secondaries.JobServer.Alerts.Refresh()
                }
            }

            if ($Exclude -notcontains "AgentProxy") {
                if ($PSCmdlet.ShouldProcess("Syncing Agent Proxy Accounts from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Proxy Accounts"
                    Copy-DbaAgentProxy -Source $server -Destination $secondaries -Force:$force
                    $secondaries.JobServer.ProxyAccounts.Refresh()
                }
            }

            if ($Exclude -notcontains "AgentSchedule") {
                if ($PSCmdlet.ShouldProcess("Syncing Agent Schedules from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Schedules"
                    Copy-DbaAgentSchedule -Source $server -Destination $secondaries -Force:$force
                    $secondaries.JobServer.SharedSchedules.Refresh()
                    $secondaries.JobServer.Refresh()
                    $secondaries.Refresh()
                }
            }

            if ($Exclude -notcontains "AgentJob") {
                if ($PSCmdlet.ShouldProcess("Syncing Agent Jobs from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Jobs"
                    Copy-DbaAgentJob -Source $server -Destination $secondaries -Force:$force -Job $Job -ExcludeJob $ExcludeJob
                }
            }

            if ($Exclude -notcontains "LoginPermissions") {
                if ($PSCmdlet.ShouldProcess("Syncing login permissions from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing login permissions"
                    Sync-DbaLoginPermission -Source $server -Destination $secondaries -Login $Login -ExcludeLogin $ExcludeLogin
                }
            }
        }
    }
}
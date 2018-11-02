#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Sync-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Syncs jobs, logins, whatnot for availability groups

    .DESCRIPTION
        Syncs jobs, logins, whatnot for availability groups
    
    .PARAMETER Primary
        The primary SQL Server instance. Server version must be SQL Server version 2012 or higher.

    .PARAMETER PrimarySqlCredential
        Login to the primary instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Secondary
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SecondarySqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
        
    .PARAMETER InputObject
        Enables piping from Get-DbaAvailabilityGroup.
    
    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: HA
        Author: Chrissy LeMaire (@cl), netnerds.net
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Sync-DbaAvailabilityGroup

    .EXAMPLE
        PS C:\> Sync-DbaAvailabilityGroup -Primary sql2016a -Name SharePoint

        Creates a new availability group on sql2016a named SharePoint
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter]$Primary,
        [PSCredential]$PrimarySqlCredential,
        [DbaInstanceParameter[]]$Secondary,
        [PSCredential]$SecondarySqlCredential,
        [string]$AvailabilityGroup,
        [ValidateSet('AgentCategory', 'AgentOperator', 'AgentAlert', 'AgentProxy', 'AgentSchedule', 'AgentJob', 'Credentials', 'CustomErrors', 'DatabaseMail', 'DatabaseOwner', 'LinkedServers', 'Logins', 'LoginPermissions', 'SpConfigure', 'SystemTriggers')]
        [string[]]$Exclude,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        $stepCounter = $wait = 0
        $totalSteps = 10
        $activity = "Syncing availability group $AvailabilityGroup"
        
        try {
            $server = Connect-SqlInstance -SqlInstance $Primary -SqlCredential $PrimarySqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Primary
            return
        }
        
       if ($Secondary) {
            $secondaries = @()
            foreach ($computer in $Secondary) {
                try {
                    $secondaries += Connect-SqlInstance -SqlInstance $computer -SqlCredential $SecondarySqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Primary
                    return
                }
            }
        }
        
        if ($AvailabilityGroup) {
            $secondaries = @()
            foreach ($computer in $Secondary) {
                try {
                    $secondaries += Connect-SqlInstance -SqlInstance $computer -SqlCredential $SecondarySqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Primary
                    return
                }
            }
        }
        
        if ($Exclude -notcontains "Logins") {
            if ($PSCmdlet.ShouldProcess("Syncing logins")) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing logins"
                Copy-DbaLogin -Source $server -Destination $secondaries -Force:$Force
            }
        }
        
        if ($Exclude -notcontains "SpConfigure") {
            if ($PSCmdlet.ShouldProcess("Syncing SQL Server Configuration")) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing SQL Server Configuration"
                Copy-DbaSpConfigure -Source $server -Destination $secondaries
            }
        }
        
        if ($Exclude -notcontains "CustomErrors") {
            if ($PSCmdlet.ShouldProcess("Syncing custom errors (user defined messages)")) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing custom errors (user defined messages)"
                Copy-DbaCustomError -Source $server -Destination $secondaries -Force:$Force
            }
        }
        
        if ($Exclude -notcontains "Credentials") {
            if ($PSCmdlet.ShouldProcess("Syncing SQL credentials")) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing SQL credentials"
                Copy-DbaCredential -Source $server -Destination $secondaries -Force:$Force
            }
        }
        
        if ($Exclude -notcontains "DatabaseMail") {
            if ($PSCmdlet.ShouldProcess("Syncing database mail")) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing database mail"
                Copy-DbaDbMail -Source $server -Destination $secondaries -Force:$Force
            }
        }
        
        if ($Exclude -notcontains "LinkedServers") {
            if ($PSCmdlet.ShouldProcess("Syncing linked servers")) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing linked servers"
                Copy-DbaLinkedServer -Source $server -Destination $secondaries -Force:$Force
            }
        }
        
        if ($Exclude -notcontains "SystemTriggers") {
            if ($PSCmdlet.ShouldProcess("Syncing System Triggers")) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing System Triggers"
                Copy-DbaServerTrigger -Source $sourceserver -Destination $secondaries -Force:$Force
            }
        }
        
        # grab dbs
        if ($Exclude -notcontains "DatabaseOwner") {
            if ($PSCmdlet.ShouldProcess("Updating database owners to match newly migrated logins")) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Updating database owners to match newly migrated logins"
                foreach ($sec in $secondaries) {
                    $null = Update-SqlDbOwner -Source $server -Destination $sec
                }
            }
        }
        
        if ($Exclude -notcontains "AgentCategory") {
            if ($PSCmdlet.ShouldProcess("Syncing Agent Categories")) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Categories"
                Copy-DbaAgentCategory -Source $sourceServer -Destination $destServer -Force:$force
                $destServer.JobServer.JobCategories.Refresh()
                $destServer.JobServer.OperatorCategories.Refresh()
                $destServer.JobServer.AlertCategories.Refresh()
            }
        }
        
        if ($Exclude -notcontains "AgentOperator") {
            if ($PSCmdlet.ShouldProcess("Syncing Agent Operators")) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Operators"
                Copy-DbaAgentOperator -Source $sourceServer -Destination $destServer -Force:$force
                $destServer.JobServer.Operators.Refresh()
            }
        }
        
        if ($Exclude -notcontains "AgentAlert") {
            if ($PSCmdlet.ShouldProcess("Syncing Agent Alerts")) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Alerts"
                Copy-DbaAgentAlert -Source $sourceServer -Destination $destServer -Force:$force -IncludeDefaults
                $destServer.JobServer.Alerts.Refresh()
            }
        }
        
        if ($Exclude -notcontains "AgentProxy") {
            if ($PSCmdlet.ShouldProcess("Syncing Agent Proxy Accounts")) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Proxy Accounts"
                Copy-DbaAgentProxyAccount -Source $sourceServer -Destination $destServer -Force:$force
                $destServer.JobServer.ProxyAccounts.Refresh()
            }
        }
        
        if ($Exclude -notcontains "AgentSchedule") {
            if ($PSCmdlet.ShouldProcess("Syncing Agent Schedules")) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Schedules"
                Copy-DbaAgentSharedSchedule -Source $sourceServer -Destination $destServer -Force:$force
                $destServer.JobServer.SharedSchedules.Refresh()
                $destServer.JobServer.Refresh()
                $destServer.Refresh()
            }
        }
        
        if ($Exclude -notcontains "AgentJob") {
            if ($PSCmdlet.ShouldProcess("Syncing Agent Jobs")) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Jobs"
                Copy-DbaAgentJob -Source $sourceServer -Destination $destServer -Force:$force -DisableOnDestination:$DisableJobsOnDestination -DisableOnSource:$DisableJobsOnSource
            }
        }
        
        if ($Exclude -notcontains "LoginPermissions") {
            if ($PSCmdlet.ShouldProcess("Syncing login permissions")) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing login permissions"
                Sync-DbaLoginPermission -Source $server -Destination $secondaries
            }
        }
    }
}
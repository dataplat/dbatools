function Set-DbaAgentAlert {
    <#
    .SYNOPSIS
        Modifies properties of existing SQL Agent alerts including enabled status and name.

    .DESCRIPTION
        Modifies existing SQL Agent alerts on one or more SQL Server instances, allowing you to enable, disable, or rename alerts without using SQL Server Management Studio. This function is particularly useful for bulk operations across multiple servers, standardizing alert configurations between environments, or temporarily disabling noisy alerts during maintenance windows. The function works with the JobServer.Alerts collection and uses the SMO Alter() method to commit changes to existing alerts. You can specify alerts by name or pipe in alert objects from other dbatools commands like Get-DbaAgentAlert.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Alert
        Specifies the name(s) of the SQL Agent alerts to modify. Accepts multiple alert names for bulk operations.
        Use this when you need to update specific alerts by name across one or more instances.

    .PARAMETER NewName
        Sets a new name for the alert being modified. Only works when modifying a single alert.
        Use this when standardizing alert names across environments or fixing naming conventions.

    .PARAMETER Enabled
        Enables the specified SQL Agent alert(s) by setting IsEnabled to true.
        Use this to reactivate alerts after maintenance or to ensure critical alerts are active across all instances.

    .PARAMETER Disabled
        Disables the specified SQL Agent alert(s) by setting IsEnabled to false.
        Use this during maintenance windows or to silence noisy alerts that are firing incorrectly.

    .PARAMETER Force
        Bypasses confirmation prompts by setting ConfirmPreference to 'none'.
        Use this in automated scripts where you want to suppress interactive prompts.

    .PARAMETER InputObject
        Accepts SQL Agent alert objects from the pipeline, typically from Get-DbaAgentAlert.
        Use this when you want to filter alerts first, then modify the results in a pipeline operation.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Alert
        Author: Garry Bargsley (@gbargsley), garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaAgentAlert

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Agent.Alert

        Returns one Alert object for each alert that was modified. The returned objects include all properties from the Alert object with added connection context properties.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the alert
        - IsEnabled: Boolean indicating if the alert is currently enabled
        - NotificationMessage: The message sent when the alert fires
        - AlertType: Type of alert (EventAlert, PerformanceConditionAlert, or TransactionLogAlert)
        - Severity: The severity level that triggers this alert (if alert type is EventAlert)
        - DatabaseName: The database name the alert applies to (if applicable)
        - EventDescriptionKeyword: Keywords in the error message that trigger the alert
        - LastOccurrenceDate: DateTime of the last time this alert was triggered
        - OccurrenceCount: Number of times this alert has been triggered

        Additional properties available (from SMO Alert object):
        - ID: Unique identifier for the alert
        - CreateDate: DateTime when the alert was created
        - DateLastModified: DateTime when the alert was last modified
        - JobName: The SQL Agent job to execute when the alert fires
        - PerformanceCondition: The performance condition that triggers the alert
        - HasNotification: Boolean indicating if notification methods are configured

        All properties from the base SMO Alert object are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> Set-DbaAgentAlert -SqlInstance sql1 -Alert 'Severity 025: Fatal Error' -Disabled

        Changes the alert to disabled.

    .EXAMPLE
        PS C:\> Set-DbaAgentAlert -SqlInstance sql1 -Alert 'Severity 025: Fatal Error', 'Error Number 825', 'Error Number 824' -Enabled

        Changes multiple alerts to enabled.

    .EXAMPLE
        PS C:\> Set-DbaAgentAlert -SqlInstance sql1, sql2, sql3 -Alert 'Severity 025: Fatal Error', 'Error Number 825', 'Error Number 824' -Enabled

        Changes multiple alerts to enabled on multiple servers.

    .EXAMPLE
        PS C:\> Set-DbaAgentAlert -SqlInstance sql1 -Alert 'Severity 025: Fatal Error' -Disabled -WhatIf

        Doesn't Change the alert but shows what would happen.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Alert,
        [string]$NewName,
        [switch]$Enabled,
        [switch]$Disabled,
        [switch]$Force,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Alert[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {

        if (Test-FunctionInterrupt) { return }

        if ((-not $InputObject) -and (-not $Alert)) {
            Stop-Function -Message "You must specify an alert name or pipe in results from another command" -Target $SqlInstance
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            foreach ($a in $Alert) {
                # Check if the alert exists
                if ($server.JobServer.Alerts.Name -notcontains $a) {
                    Stop-Function -Message "Alert $a doesn't exists on $instance" -Target $instance
                } else {
                    # Get the alert
                    try {
                        $InputObject += $server.JobServer.Alerts[$a]

                        # Refresh the object
                        $InputObject.Refresh()
                    } catch {
                        Stop-Function -Message "Something went wrong retrieving the alert" -Target $a -ErrorRecord $_ -Continue
                    }
                }
            }
        }

        foreach ($currentAlert in $InputObject) {
            $server = $currentAlert.Parent.Parent

            #region alert options
            # Settings the options for the alert
            if ($NewName) {
                if ($Pscmdlet.ShouldProcess($server, "Setting alert name to $NewName for $currentAlert")) {
                    $currentAlert.Rename($NewName)
                }
            }

            if ($Enabled) {
                Write-Message -Message "Setting alert to enabled" -Level Verbose
                $currentAlert.IsEnabled = $true
            }

            if ($Disabled) {
                Write-Message -Message "Setting alert to disabled" -Level Verbose
                $currentAlert.IsEnabled = $false
            }

            #endregion alert options

            # Execute
            if ($PSCmdlet.ShouldProcess($SqlInstance, "Committing changes for alert $a")) {
                try {
                    Write-Message -Message "Committing changes for alert $a" -Level Verbose

                    # Change the alert
                    $currentAlert.Alter()
                } catch {
                    Stop-Function -Message "Something went wrong changing the alert" -ErrorRecord $_ -Target $instance -Continue
                }
                Get-DbaAgentAlert -SqlInstance $server | Where-Object Name -eq $currentAlert.name
            }
        }
    }
}
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
        The name of the alert.

    .PARAMETER NewName
        The new name for the alert.

    .PARAMETER Enabled
        Enabled the alert.

    .PARAMETER Disabled
        Disabled the alert.

    .PARAMETER Force
        The force parameter will ignore some errors in the parameters and assume defaults.

    .PARAMETER InputObject
        Enables piping alert objects

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
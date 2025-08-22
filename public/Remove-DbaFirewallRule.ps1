function Remove-DbaFirewallRule {
    <#
    .SYNOPSIS
        Removes Windows firewall rules for SQL Server Engine, Browser, and DAC connections from target computers.

    .DESCRIPTION
        Removes Windows firewall rules for SQL Server components from target computers, cleaning up network access rules when decommissioning instances or changing security configurations. This command only works with firewall rules that were previously created using New-DbaFirewallRule, as it relies on specific naming conventions and rule groups.

        The function can remove rules for SQL Server Engine connections (typically port 1433 for default instances), SQL Server Browser service (UDP port 1434), and Dedicated Admin Connection (DAC) ports. This is particularly useful when decommissioning SQL Server instances, changing network security policies, or troubleshooting connectivity issues.

        This command executes Remove-NetFirewallRule remotely on target computers using PowerShell remoting, so it requires appropriate permissions and network connectivity to the target systems. The function provides detailed status reporting for each removal operation, including success status and any warnings or errors encountered.

        The functionality is currently limited to rules created by dbatools. Future versions may introduce breaking changes, so review scripts after updating dbatools.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER Type
        Removes firewall rules for the given type(s).

        Valid values are:
        * Engine - for the SQL Server instance
        * Browser - for the SQL Server Browser
        * DAC - for the dedicated admin connection (DAC)
        * AllInstance - for all firewall rules on the target computer related to SQL Server

        The default is @('Engine', 'DAC').
        As the Browser might be needed by other instances, the firewall rule for the SQL Server Browser is
        never removed with the firewall rule of the instance but only removed if 'Browser' is used.

    .PARAMETER InputObject
        The output object(s) from Get-DbaFirewallRule.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Firewall, Network, Connection
        Author: Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaFirewallRule

    .EXAMPLE
        PS C:\> Remove-DbaFirewallRule -SqlInstance SRV1

        Removes the firewall rule for the default instance on SRV1.

    .EXAMPLE
        PS C:\> Remove-DbaFirewallRule -SqlInstance SRV1\SQL2016 -Type Engine, Browser

        Removes the firewall rule for the instance SQL2016 on SRV1 and the firewall rule for the SQL Server Browser.

    .EXAMPLE
        PS C:\> Get-DbaFirewallRule -SqlInstance SRV1 -Type AllInstance | Where-Object Type -eq 'Engine' | Remove-DbaFirewallRule

        Removes the firewall rules for all instance from SRV1. Leaves the firewall rule for the SQL Server Browser in place.

    .EXAMPLE
        PS C:\> Remove-DbaFirewallRule -SqlInstance SRV1 -Confirm:$false

        Removes the firewall rule for the default instance on SRV1. Does not prompt for confirmation.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High", DefaultParameterSetName = 'NonPipeline')]
    param (
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [PSCredential]$Credential,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [ValidateSet('Engine', 'Browser', 'DAC', 'AllInstance')]
        [string[]]$Type = @('Engine', 'DAC'),
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [object[]]$InputObject,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $cmdScriptBlock = {
            # This scriptblock will be processed by Invoke-Command2.
            # Since only rules that were previously determined with Get-NetFirewallRule are deleted, there should be no problems.
            $firewallRuleName = $args[0]

            try {
                $successful = $true
                $null = Remove-NetFirewallRule -Name $firewallRuleName -WarningVariable warn -ErrorVariable err -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                if ($warn.Count -gt 0) {
                    $successful = $false
                } else {
                    # Change from an empty System.Collections.ArrayList to $null for better readability
                    $warn = $null
                }
                if ($err.Count -gt 0) {
                    $successful = $false
                } else {
                    # Change from an empty System.Collections.ArrayList to $null for better readability
                    $err = $null
                }
                [PSCustomObject]@{
                    Successful = $successful
                    Warning    = $warn
                    Error      = $err
                    Exception  = $null
                }
            } catch {
                [PSCustomObject]@{
                    Successful = $false
                    Warning    = $null
                    Error      = $null
                    Exception  = $_
                }
            }
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Get firewall rules from $($instance.ComputerName)."
                $InputObject += Get-DbaFirewallRule -SqlInstance $instance -Credential $Credential -Type $Type -EnableException
            } catch {
                Stop-Function -Message "Failed to collect firewall rules from $($instance.ComputerName)." -Target $instance -ErrorRecord $_ -Continue
            }
        }

        foreach ($rule in $InputObject) {
            if ($PSCmdlet.ShouldProcess($rule.ComputerName, "Removing firewall rule $($rule.Name)")) {
                try {
                    Write-Message -Level Debug -Message "Executing Invoke-Command2 with ComputerName = $($rule.ComputerName) and ArgumentList $($rule.Name)."
                    $commandResult = Invoke-Command2 -ComputerName $rule.ComputerName -Credential $rule.Credential -ScriptBlock $cmdScriptBlock -ArgumentList $rule.Name
                } catch {
                    Stop-Function -Message "Failed to execute command on $($rule.ComputerName)." -Target $instance -ErrorRecord $_ -Continue
                }

                if ($commandResult.Successful) {
                    $status = 'The rule was successfully removed.'
                } else {
                    $status = 'Failure.'
                }
                if ($commandResult.Warning) {
                    Write-Message -Level Verbose -Message "commandResult.Warning: $($commandResult.Warning)."
                    $status += " Warning: $($commandResult.Warning)."
                }
                if ($commandResult.Error) {
                    Write-Message -Level Verbose -Message "commandResult.Error: $($commandResult.Error)."
                    $status += " Error: $($commandResult.Error)."
                }
                if ($commandResult.Exception) {
                    Write-Message -Level Verbose -Message "commandResult.Exception: $($commandResult.Exception)."
                    $status += " Exception: $($commandResult.Exception)."
                }

                # Output information
                [PSCustomObject]@{
                    ComputerName = $rule.ComputerName
                    InstanceName = $rule.InstanceName
                    SqlInstance  = $rule.SqlInstance
                    DisplayName  = $rule.DisplayName
                    Type         = $rule.Type
                    IsRemoved    = $commandResult.Successful
                    Status       = $status
                } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, DisplayName, Type, IsRemoved, Status
            }
        }
    }
}
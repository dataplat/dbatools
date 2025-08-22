function Set-DbaSpConfigure {
    <#
    .SYNOPSIS
        Modifies SQL Server instance-level configuration settings through sp_configure

    .DESCRIPTION
        This function safely modifies SQL Server instance-level configuration values that are normally changed through sp_configure. Use this when you need to adjust settings like max memory, xp_cmdshell, cost threshold for parallelism, or any other server configuration option.

        For dynamic settings, changes take effect immediately. For static settings, you'll receive a warning that SQL Server must be restarted before the new value becomes active.

        Built-in safety prevents setting values outside their defined minimum and maximum ranges, protecting against configuration errors that could prevent SQL Server from starting or cause performance issues.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a
        collection and receive pipeline input

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        The name of the configuration to be set -- Configs is auto-populated for tabbing convenience.

    .PARAMETER Value
        The new value for the configuration

    .PARAMETER InputObject
        Piped objects from Get-DbaSpConfigure

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .NOTES
        Tags: SpConfigure
        Author: Nic Cain, sirsql.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaSpConfigure

    .EXAMPLE
        PS C:\> Set-DbaSpConfigure -SqlInstance localhost -Name ScanForStartupProcedures -Value 1

        Adjusts the Scan for startup stored procedures configuration value to 1 and notifies the user that this requires a SQL restart to take effect

    .EXAMPLE
        PS C:\> Get-DbaSpConfigure -SqlInstance sql2017, sql2014 -Name XPCmdShellEnabled, IsSqlClrEnabled | Set-DbaSpConfigure -Value $false

        Sets the values for XPCmdShellEnabled and IsSqlClrEnabled on sql2017 and sql2014 to False

    .EXAMPLE
        PS C:\> Set-DbaSpConfigure -SqlInstance localhost -Name XPCmdShellEnabled -Value 1

        Adjusts the xp_cmdshell configuration value to 1.

    .EXAMPLE
        PS C:\> Set-DbaSpConfigure -SqlInstance localhost -Name XPCmdShellEnabled -Value 1 -WhatIf

        Returns information on the action that would be performed. No actual change will be made.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [Alias("NewValue", "NewConfig")]
        [int]$Value,
        [Alias("Config", "ConfigName")]
        [string[]]$Name,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -ParameterName SqlInstance) {
            $InputObject += Get-DbaSpConfigure -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Name $Name
        }

        foreach ($configobject in $InputObject) {
            $server = $configobject.Parent
            $currentRunValue = $configobject.RunningValue
            $currentConfigValue = $configobject.ConfiguredValue
            $minValue = $configobject.MinValue
            $maxValue = $configobject.MaxValue
            $isDynamic = $configobject.IsDynamic
            $configuration = $configobject.Name

            #Let us not waste energy setting the value to itself
            if ($currentConfigValue -eq $value) {
                Stop-Function -Message "Value to set is the same as the existing value. No work being performed." -Continue -Target $server -Category InvalidData
            }

            #Going outside the min/max boundary can be done, but it can break SQL, so I don't think allowing that is wise at this juncture
            if ($value -lt $minValue -or $value -gt $maxValue) {
                Stop-Function -Message "Value out of range for $configuration ($minValue <-> $maxValue)" -Continue -Category InvalidArgument
            }

            If ($Pscmdlet.ShouldProcess($SqlInstance, "Adjusting server configuration $configuration from $currentConfigValue to $value.")) {
                try {
                    $configobject.Property.ConfigValue = $value
                    $server.Configuration.Alter()

                    [PSCustomObject]@{
                        ComputerName  = $server.ComputerName
                        InstanceName  = $server.ServiceName
                        SqlInstance   = $server.DomainInstanceName
                        ConfigName    = $configuration
                        PreviousValue = $currentConfigValue
                        NewValue      = $value
                    }

                    #If it's a dynamic setting we're all clear, otherwise let the user know that SQL needs to be restarted for the change to take
                    if ($isDynamic -eq $false) {
                        Write-Message -Level Warning -Message "Configuration setting $configuration has been set, but restart of SQL Server is required for the new value `"$value`" to be used (old value: `"$currentRunValue`")" -Target $Instance
                    }
                } catch {
                    Stop-Function -Message "Unable to change config setting" -Target $Instance -ErrorRecord $_ -Continue -ContinueLabel main
                }
            }
        }
    }
}
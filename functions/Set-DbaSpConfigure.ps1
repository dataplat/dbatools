function Set-DbaSpConfigure {
    <#
        .SYNOPSIS
            Changes the server level system configuration (sys.configuration/sp_configure) value for a given configuration

        .DESCRIPTION
            This function changes the configured value for sp_configure settings. If the setting is dynamic this setting will be used, otherwise the user will be warned that a restart of SQL is required.
            This is designed to be safe and will not allow for configurations to be set outside of the defined configuration min and max values.
            While it is possible to set below the min, or above the max this can cause serious problems with SQL Server (including startup failures), and so is not permitted.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a
            collection and receive pipeline input

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Name
            The name of the configuration to be set -- Configs is auto-populated for tabbing convenience.

        .PARAMETER Value
            The new value for the configuration

        .PARAMETER InputObject
            Piped objectgs from Get-DbaSpConfigure
    
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
            Author: Nic Cain, https://sirsql.net/

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Set-DbaSpConfigure

        .EXAMPLE
            Set-DbaSpConfigure -SqlInstance localhost -Name ScanForStartupProcedures -Value 1

            Adjusts the Scan for startup stored procedures configuration value to 1 and notifies the user that this requires a SQL restart to take effect

        .EXAMPLE
            Get-DbaSpConfigure -SqlInstance sql2017, sql2014 -Name XPCmdShellEnabled, IsSqlClrEnabled | Set-DbaSpConfigure -Value $false
            Sets the values for XPCmdShellEnabled and IsSqlClrEnabled on sql2017 and sql2014 to False
    
        .EXAMPLE
            Set-DbaSpConfigure -SqlInstance localhost -Name XPCmdShellEnabled -Value 1

            Adjusts the xp_cmdshell configuration value to 1.

        .EXAMPLE
            Set-DbaSpConfigure -SqlInstance localhost -Name XPCmdShellEnabled -Value 1 -WhatIf

            Returns information on the action that would be performed. No actual change will be made.
        #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [Alias("NewValue", "NewConfig")]
        [int]$Value,
        [Alias("Config", "ConfigName")]
        [string[]]$Name,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch][Alias('Silent')]
        $EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaSpConfigure -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Name $Name
        }
        
        foreach ($configobject in $InputObject) {
            $server = $InputObject.Parent
            $currentRunValue = $configobject.RunningValue
            $minValue = $configobject.MinValue
            $maxValue = $configobject.MaxValue
            $isDynamic = $configobject.IsDynamic
            $configuration = $configobject.Name
            
            #Let us not waste energy setting the value to itself
            if ($currentRunValue -eq $value) {
                Stop-Function -Message "Value to set is the same as the existing value. No work being performed." -Continue -Target $server -Category InvalidData
            }
            
            #Going outside the min/max boundary can be done, but it can break SQL, so I don't think allowing that is wise at this juncture
            if ($value -lt $minValue -or $value -gt $maxValue) {
                Stop-Function -Message "Value out of range for $configuration ($minValue <-> $maxValue)" -Continue -Category InvalidArgument
            }
            
            If ($Pscmdlet.ShouldProcess($SqlInstance, "Adjusting server configuration $configuration from $currentRunValue to $value.")) {
                try {
                    $server.Configuration.$configuration.ConfigValue = $value
                    $server.Configuration.Alter()
                    
                    [pscustomobject]@{
                        ComputerName           = $server.NetName
                        InstanceName           = $server.ServiceName
                        SqlInstance            = $server.DomainInstanceName
                        ConfigName             = $configuration
                        OldValue               = $currentRunValue
                        NewValue               = $value
                    }
                    
                    #If it's a dynamic setting we're all clear, otherwise let the user know that SQL needs to be restarted for the change to take
                    if ($isDynamic -eq $false) {
                        Write-Message -Level Warning -Message "Configuration setting $configuration has been set, but restart of SQL Server is required for the new value `"$value`" to be used (old value: `"$currentRunValue`")" -Target $Instance
                    }
                }
                catch {
                    Stop-Function -Message "Unable to change config setting" -Target $Instance -ErrorRecord $_ -Continue -ContinueLabel main
                }
            }
        }
    }
}
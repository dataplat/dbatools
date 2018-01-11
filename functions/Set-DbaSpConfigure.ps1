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
            PSCredential object to connect as. If not specified, current Windows login will be used.

        .PARAMETER ConfigName
            The name of the configuration to be set -- Configs is auto-populated for tabbing convenience.

        .PARAMETER Value
            The new value for the configuration

        .PARAMETER WhatIf
            Shows what would happen if the command were to run. No actions are actually performed.

        .PARAMETER Mode
            Default: Strict
            How strict does the command take lesser issues?
            Strict: Interrupt if the configuration already has the same value as the one specified.
            Lazy:   Silently skip over instances that already have this configuration at the specified value.

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
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Set-DbaSpConfigure

        .EXAMPLE
            Set-DbaSpConfigure -SqlInstance localhost -ConfigName ScanForStartupProcedures -value 1

            Adjusts the Scan for startup stored procedures configuration value to 1 and notifies the user that this requires a SQL restart to take effect

        .EXAMPLE
            Set-DbaSpConfigure -SqlInstance localhost -ConfigName XPCmdShellEnabled -value 1

            Adjusts the xp_cmdshell configuration value to 1.

        .EXAMPLE
            Set-DbaSpConfigure -SqlInstance localhost -ConfigName XPCmdShellEnabled -value 1 -WhatIf

            Returns information on the action that would be performed. No actual change will be made.
        #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]
        $SqlInstance,

        [System.Management.Automation.PSCredential]
        $SqlCredential,

        [Parameter(Mandatory = $false)]
        [Alias("NewValue", "NewConfig")]
        [int]
        $Value,

        [Alias("Config")]
        [object[]]
        $ConfigName,

        [ValidateSet('Strict', 'Lazy')]
        [DbaMode]
        $Mode = 'Strict',

        [switch]
        [Alias('Silent')]$EnableException
    )

    begin {
        if (!$ConfigName) {
            Stop-Function -Message "You must select one or more configurations to modify" -Target $Instance
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        :main foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            #Grab the current config value
            $currentValues = ($server.Configuration.$ConfigName)
            if ($currentValues) {
                $currentRunValue = $currentValues.RunValue
                $minValue = $currentValues.Minimum
                $maxValue = $currentValues.Maximum
                $isDynamic = $currentValues.IsDynamic

                #Let us not waste energy setting the value to itself
                if ($currentRunValue -eq $value) {
                    switch ($Mode) {
                        'Lazy' {
                            Write-Message -Level Verbose -Message "Skipping over <c='green'>$instance</c> since its <c='gray'>$ConfigName</c> is already set to <c='gray'>$Value</c>" -Target $instance
                            continue main
                        }
                        'Strict' {
                            Stop-Function -Message "Value to set is the same as the existing value. No work being performed." -Continue -ContinueLabel main -Target $instance -Category InvalidData
                        }
                    }
                }

                #Going outside the min/max boundary can be done, but it can break SQL, so I don't think allowing that is wise at this juncture
                if ($value -lt $minValue -or $value -gt $maxValue) {
                    Stop-Function -Message "Value out of range for $ConfigName ($minValue <-> $maxValue)" -Continue -Category InvalidArgument
                }

                If ($Pscmdlet.ShouldProcess($SqlInstance, "Adjusting server configuration $ConfigName from $currentRunValue to $value.")) {
                    try {
                        $server.Configuration.$ConfigName.ConfigValue = $value
                        $server.Configuration.Alter()

                        [pscustomobject]@{
                            ComputerName = $server.NetName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            ConfigName   = $ConfigName
                            OldValue     = $currentRunValue
                            NewValue     = $value
                        }

                        #If it's a dynamic setting we're all clear, otherwise let the user know that SQL needs to be restarted for the change to take
                        if ($isDynamic -eq $false) {
                            Write-Message -Level Warning -Message "Configuration setting $ConfigName has been set, but restart of SQL Server is required for the new value `"$value`" to be used (old value: `"$currentRunValue`")" -Target $Instance
                        }
                    }
                    catch {
                        Stop-Function -Message "Unable to change config setting" -Target $Instance -ErrorRecord $_ -Continue -ContinueLabel main
                    }
                }
            }
            else {
                Stop-Function -Message "Config setting $ConfigName not found" -Target $Instance -ErrorRecord $_ -Continue -ContinueLabel main
            }
        }
    }
}
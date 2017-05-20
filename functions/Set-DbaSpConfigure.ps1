FUNCTION Set-DbaSpConfigure
{
<#
.SYNOPSIS
Changes the server level system configuration (sys.configuration/sp_configure) value for a given configuration

.DESCRIPTION
This function changes the configured value for sp_configure settings. If the setting is dynamic this setting will be used, otherwise the user will be warned that a restart of SQL is required.
This is designed to be safe and will not allow for configurations to be set outside of the defined configuration min and max values. 
While it is possible to set below the min, or above the max this can cause serious problems with SQL Server (including startup failures), and so is not permitted.

.PARAMETER SqlInstance
SQLServer name or SMO object representing the SQL Server to connect to. This can be a
collection and recieve pipeline input

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, current Windows login will be used.

.PARAMETER Configs
The name of the configuration to be set -- Configs is autopopulated for tabbing convenience. 
	
.PARAMETER Value
The new value for the configuration

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command.

.NOTES 
Original Author: Nic Cain, https://sirsql.net/
Tags: Config
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.LINK
https://dbatools.io/Set-DbaSpConfigure

.EXAMPLE
Set-DbaSpConfigure -SqlInstance localhost -configs ScanForStartupProcedures -value 1
Adjusts the Scan for startup stored procedures configuration value to 1 and notifies the user that this requires a SQL restart to take effect

.EXAMPLE
Set-DbaSpConfigure -SqlInstance localhost -configs XPCmdShellEnabled -value 1
Adjusts the xp_cmdshell configuation value to 1.

.EXAMPLE
Set-DbaSpConfigure -SqlInstance localhost -configs XPCmdShellEnabled -value 1 -WhatIf
Returns information on the action that would be performed. No actual change will be made.


#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer")]
		[string[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[Parameter(Mandatory = $false)]
		[Alias("NewValue", "NewConfig")]
		[int]$Value,
		[switch]$Silent
	)
	

	
	begin
	{
		$configs = $psboundparameters.Configs
		
		if (!$configs)
		{
			Stop-Function -Message "You must select one or more configurations to modify" -Target $Instance
		}
	}
	
	process
	{
		if (Test-FunctionInterrupt) { return }
		
		foreach ($instance in $SqlInstance)
		{
			try
			{
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch
			{
				Stop-Function -Message "Failed to connect to: $instance" -Continue -Target $Instance
			}
			
			#Grab the current config value
			$currentValues = ($server.Configuration.$configs)
			$currentRunValue = $currentValues.RunValue
			$minValue = $currentValues.Minimum
			$maxValue = $currentValues.Maximum
			$isDynamic = $currentValues.IsDynamic
			
			#Let us not waste energy setting the value to itself
			if ($currentRunValue -eq $value)
			{
				Stop-Function -Message "Value to set is the same as the existing value. No work being performed." -Continue
			}
			
			#Going outside the min/max boundary can be done, but it can break SQL, so I don't think allowing that is wise at this juncture
			if ($value -lt $minValue -or $value -gt $maxValue)
			{
				Stop-Function -Message "Value out of range for $configs (min: $minValue - max $maxValue)" -Continue
			}
			
			If ($Pscmdlet.ShouldProcess($SqlInstance, "Adjusting server configuration $configs from $currentRunValue to $value."))
			{
				try
				{
					$server.Configuration.$configs.ConfigValue = $value
					$server.Configuration.Alter()
					
					[pscustomobject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.DomainInstanceName
						OldValue = $currentRunValue
						NewValue = $value
					}
					
					#If it's a dynamic setting we're all clear, otherwise let the user know that SQL needs to be restarted for the change to take
					if ($isDynamic -eq $false)
					{
						Write-Message -Level Warning -Message "Config set for $configs, but restart of SQL Server is required for the new value ($value) to be used (old value: $($value))" -Target $Instance
					}
				}
				catch
				{
					Write-Message -Level Warning -Message "Unable to change config setting" -Target $Instance
				}
			}
		}
	}
}

FUNCTION Get-DbaSpConfigure
{
<#
.SYNOPSIS
Returns all server level system configuration (sys.configuration/sp_configure) information

.DESCRIPTION
This function returns server level system configuration (sys.configuration/sp_configure) information. The information is gathered through SMO Configuration.Properties.
The data includes the default value for each configuration, for quick identification of values that may have been changed.

.PARAMETER SqlInstance
SQLServer name or SMO object representing the SQL Server to connect to. This can be a
collection and recieve pipeline input

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, current Windows login will be used.

.PARAMETER Configs
Return only specific configurations -- auto-populated from source server
	
.PARAMETER Detailed
Returns more information about the configuration settings than standard

.NOTES 
Original Author: Nic Cain, https://sirsql.net/
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.LINK
https://dbatools.io/Get-DbaSpConfigure

.EXAMPLE
Get-DbaSpConfigure -SqlInstance localhost
Returns server level configuration data on the localhost (ServerName, ConfigName, DisplayName, Description, IsAdvanced, IsDynamic, MinValue, MaxValue, ConfiguredValue, RunningValue, DefaultValue, IsRunningDefaultValue)

.EXAMPLE
'localhost','localhost\namedinstance' | Get-DbaSpConfigure
Returns system configuration information on multiple instances piped into the function

.EXAMPLE
Get-DbaSpConfigure -SqlInstance localhost
Returns server level configuration data on the localhost (ServerName, ConfigName, DisplayName, Description, IsAdvanced, IsDynamic, MinValue, MaxValue, ConfiguredValue, RunningValue, DefaultValue, IsRunningDefaultValue)

.EXAMPLE
Get-DbaSpConfigure -SqlInstance sql2012 -Configs MaxServerMemory

Returns only the system configuration for MaxServerMemory. Configs is autopopulated for tabbing convenience. 

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer", "SqlServers")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	

	
	BEGIN
	{
		$configs = $psboundparameters.Configs
	}
	
	PROCESS
	{
		FOREACH ($instance in $SqlInstance)
		{
			TRY
			{
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			CATCH
			{
				Write-Warning "Failed to connect to: $instance"
				continue
			}
			
			#Get a list of the configuration property parents, and exlude the Parent, Properties values
			$proplist = Get-Member -InputObject $server.Configuration -MemberType Property -Force | Select-Object Name | Where-Object { $_.Name -ne "Parent" -and $_.Name -ne "Properties" }
			
			if ($configs)
			{
				$proplist = $proplist | Where-Object { $_.Name -in $configs }
			}
			
			#Grab the default sp_configure property values from the external function
			$defaultConfigs = (Get-SqlDefaultSpConfigure -SqlVersion $server.VersionMajor).psobject.properties;
			
			#Iterate through the properties to get the configuration settings
			foreach ($prop in $proplist)
			{
				$propInfo = $server.Configuration.$($prop.Name)
				$defaultConfig = $defaultConfigs | Where-Object { $_.Name -eq $propInfo.DisplayName };
				
				if ($defaultConfig.Value -eq $propInfo.RunValue) { $isDefault = $true }
				else { $isDefault = $false }
				
				#Ignores properties that are not valid on this version of SQL
				if (!([string]::IsNullOrEmpty($propInfo.RunValue)))
				{
					# some displaynames were empty
					$displayname = $propInfo.DisplayName
					if ($displayname.Length -eq 0) { $displayname = $prop.Name }
					
					[pscustomobject]@{
						ServerName = $server.Name
						ConfigName = $prop.Name
						DisplayName = $displayname
						Description = $propInfo.Description
						IsAdvanced = $propInfo.IsAdvanced
						IsDynamic = $propInfo.IsDynamic
						MinValue = $propInfo.Minimum
						MaxValue = $propInfo.Maximum
						ConfiguredValue = $propInfo.ConfigValue
						RunningValue = $propInfo.RunValue
						DefaultValue = $defaultConfig.Value
						IsRunningDefaultValue = $isDefault
					}
				}
			}
		}
	}
}

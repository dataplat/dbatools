FUNCTION Get-DbaConfiguration
{
<#
.SYNOPSIS
Returns all server level system configuration (sys.configuration/sp_configure) information

.DESCRIPTION
This function returns server level system configuration (sys.configuration/sp_configure) information. The information is gathered through SMO Configuration.Properties and be returned either in detailed or standard format

.PARAMETER SqlServer
SQLServer name or SMO object representing the SQL Server to connect to. This can be a
collection and recieve pipeline input

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, current Windows login will be used.

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
https://dbatools.io/Get-DbaConfiguration

.EXAMPLE
Get-DbaConfiguration -SqlServer localhost
Returns server level configuration data on the localhost (ServerName, ConfigName, DisplayName, ConfiguredValue, CurrentlyRunningValue)

.EXAMPLE
Get-DbaConfiguration -SqlServer localhost -Detailed
Returns detailed information on server level configuration data on the localhost (ServerName, ConfigName, DisplayName, Description, IsAdvanced, IsDynamic, MinValue, MaxValue, ConfiguredValue, CurrentlyRunningValue)

.EXAMPLE
'localhost','localhost\namedinstance' | Get-DbaConfiguration
Returns system configuration information on multiple instances piped into the function

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlInstance", "SqlServers")]
		[string[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$Detailed
	)
	BEGIN
	{
		$output = @()
	}
	PROCESS
	{
		FOREACH ($Server in $SqlServer)
		{
			TRY
			{
				$server = Connect-SqlServer -SqlServer $server -SqlCredential $sqlcredential
			}
			CATCH
			{
				Write-Verbose "Failed to connect to: $Server"
				continue
			}
			
			#Get a list of the configuration property parents, and exlude the Parent, Properties values
			$objList = get-member -InputObject $server.Configuration -MemberType Property -Force | select Name | where { $_.Name -ne "Parent" -and $_.Name -ne "Properties" }
			
			#Iterate through the properties to get the configuration settings
			foreach ($prop in $objList)
			{
				$PropInfo = $server.Configuration.$($prop.Name)
				
				#Ignores properties that are not valid on this version of SQL
				if (!([string]::IsNullOrEmpty($PropInfo.RunValue)))
				{
					$output += [pscustomobject]@{
						ServerName = $server.Name
						ConfigName = $($prop.Name)
						DisplayName = $PropInfo.DisplayName
						Description = $PropInfo.Description
						IsAdvanced = $PropInfo.IsAdvanced
						IsDynamic = $PropInfo.IsDynamic
						MinValue = $PropInfo.Minimum
						MaxValue = $PropInfo.Maximum
						ConfiguredValue = $PropInfo.ConfigValue
						CurrentlyRunningValue = $PropInfo.RunValue
					}
				}
			}
			
			if ($Detailed -eq $true)
			{
				$output | Sort-Object ServerName, DisplayName
			}
			else
			{
				$output | Sort-Object ServerName, DisplayName | Select-Object ServerName, ConfigName, DisplayName, ConfiguredValue, CurrentlyRunningValue
			}
		}
	}
}
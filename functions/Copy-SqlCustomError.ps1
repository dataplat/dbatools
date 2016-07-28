Function Copy-SqlCustomError
{
<#
.SYNOPSIS 
Copy-SqlCustomError migrates custom errors (user defined messages) from one SQL Server to another. 

.DESCRIPTION
By default, all  custom errors are copied. The -CustomErrors parameter is autopopulated for command-line completion and can be used to copy only specific custom errors.

If the custom error already exists on the destination, it will be skipped unless -Force is used. Interesting fact, if you drop the us_english version, all the other languages will be dropped for that specific ID as well.

Also, the us_english version must be created first.
	
.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlCustomError

.EXAMPLE   
Copy-SqlCustomError -Source sqlserver2014a -Destination sqlcluster

Copies all server custom errors from sqlserver2014a to sqlcluster, using Windows credentials. If custom errors with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-SqlCustomError -Source sqlserver2014a -Destination sqlcluster -Trigger 60000 -SourceSqlCredential $cred -Force

Copies a single custom error, the custom error with ID number 6000 from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a custom error with the same name exists on sqlcluster, it will be updated because -Force was used.

.EXAMPLE   
Copy-SqlCustomError -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

Shows what would happen if the command were executed using force.
#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[switch]$Force
	)
	DynamicParam { if ($source) { return (Get-ParamSqlCustomErrors -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	BEGIN
	{
		$customerrors = $psboundparameters.CustomErrors
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9)
		{
			throw "Custom Errors are only supported in SQL Server 2000 and above. Quitting."
		}
	}
	
	PROCESS
	{
		
		
		# Us has to go first
		$orderedcustomerrors = @($sourceserver.UserDefinedMessages | Where-Object { $_.Language -eq "us_english" })
		$orderedcustomerrors += $sourceserver.UserDefinedMessages | Where-Object { $_.Language -ne "us_english" }
		$destcustomerrors = $destserver.UserDefinedMessages
		
		foreach ($customerror in $orderedcustomerrors)
		{
			$customerrorid = $customerror.ID
			$language = $customerror.language.ToString()
			
			if ($customerrors.length -gt 0 -and $customerrors -notcontains $customerrorid) { continue }
			
			if ($destcustomerrors.ID -contains $customerror.ID)
			{
				if ($force -eq $false)
				{
					Write-Warning "Custom error $customerrorid $language exists at destination. Use -Force to drop and migrate."
					continue
				}
				else
				{
					If ($Pscmdlet.ShouldProcess($destination, "Dropping custom error $customerrorid $language and recreating"))
					{
						try
						{
							Write-Verbose "Dropping custom error $customerrorid (drops all languages for custom error $customerrorid)"
							$destserver.UserDefinedMessages[$customerrorid, $language].Drop()
						}
						catch 
						{ 
							Write-Exception $_ 
							continue
						}
					}
				}
			}
			
			If ($Pscmdlet.ShouldProcess($destination, "Creating custom error $customerrorid $language"))
			{
				try
				{
					Write-Output "Copying custom error $customerrorid $language"
					$sql = $customerror.Script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
					Write-Verbose $sql
					$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
				}
				catch
				{
					Write-Exception $_
				}
			}
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Custom error migration finished" }
	}
} 
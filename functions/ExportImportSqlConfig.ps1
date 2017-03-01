Function Export-SqlSpConfigure
{
<#
.SYNOPSIS
 Exports advanced sp_configure global configuration options to sql file.

.DESCRIPTION
Exports advanced sp_configure global configuration options to sql file.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Path
The Path to the SQL File

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.NOTES
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.EXAMPLE
Export-SqlSpConfigure $sourceserver -Path C:\temp\sp_configure.sql

Exports the SPConfigure on sourceserver to the file C:\temp\sp_configure.sql

.OUTPUTS
File to disk, and string path.

#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[string]$Path,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	BEGIN
	{
		$server = Connect-SqlServer $SqlServer $SqlCredential
		
		if ($server.versionMajor -lt 9) { "Windows 2000 not supported for sp_configure export."; break }
		
		if ($path.length -eq 0)
		{
			$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
			$mydocs = [Environment]::GetFolderPath('MyDocuments')
			$path = "$mydocs\$($server.name.replace('\', '$'))-$timenow-sp_configure.sql"
		}
	
	}
	
	PROCESS
		{
		try { Set-Content -Path $path "EXEC sp_configure 'show advanced options' , 1;  RECONFIGURE WITH OVERRIDE" }
		catch { throw "Can't write to $path" }
		
		$server.Configuration.ShowAdvancedOptions.ConfigValue = $true
		$server.Configuration.Alter($true)
		foreach ($sourceprop in $server.Configuration.Properties)
		{
			$displayname = $sourceprop.DisplayName
			$configvalue = $sourceprop.ConfigValue
			Add-Content -Path $path "EXEC sp_configure '$displayname' , $configvalue;"
		}
		Add-Content -Path $path "EXEC sp_configure 'show advanced options' , 0;"
		Add-Content -Path $Path "RECONFIGURE WITH OVERRIDE"
		$server.Configuration.ShowAdvancedOptions.ConfigValue = $false
		$server.Configuration.Alter($true)
		return $path
	}
	
	END
	{
		$server.ConnectionContext.Disconnect()
		
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message"))
		{
			Write-Output "Server configuration export finished"
		}
	}
}

Function Import-SqlSpConfigure
{
 <#
.SYNOPSIS
 Updates sp_configure settings on destination server.

.DESCRIPTION
Updates sp_configure settings on destination server.

.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, this pass this $dcred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Path
The Path to the SQL File

.PARAMETER Force
Overrides Major Version Check

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.EXAMPLE
Import-SqlSpConfigure sqlserver sqlcluster $SourceSqlCredential $DestinationSqlCredential

Imports the spconfigure settings from the source server sqlserver and sets them on the sqlcluster server
using the SQL credentials stored in the variables

.EXAMPLE
Import-SqlSpConfigure -SqlServer sqlserver -Path .\spconfig.sql -SqlCredential $SqlCredential

Imports the spconfigure settings from the file .\spconfig.sql and sets them on the sqlcluster server
using the SQL credential stored in the variables

.OUTPUTS
    $true if success
    $false if failure

#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[object]$Source,
		[object]$Destination,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[string]$Path,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$Force
		
	)
	BEGIN {
	
		if ($Path.length -eq 0)
		{
			$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
			$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
			
			$source = $sourceserver.DomainInstanceName
			$destination = $destserver.DomainInstanceName
		} else {
			$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
			if ((Test-Path $Path) -eq $false) { throw "File Not Found" }
		}
	
	}
	PROCESS
	{
		
		if ($Path.length -eq 0)
		{
			
			If ($Pscmdlet.ShouldProcess($destination, "Export sp_configure"))
			{
				$sqlfilename = Export-SqlSpConfigure $sourceserver
			}
			
			if ($sourceserver.versionMajor -ne $destserver.versionMajor -and $force -eq $false)
			{
				Write-Warning "Source SQL Server major version and Destination SQL Server major version must match for sp_configure migration. Use -Force to override this precaution or check the exported sql file, $sqlfilename, and run manually."
				return
			}
			
			If ($Pscmdlet.ShouldProcess($destination, "Execute sp_configure"))
			{
				$sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
				$sourceserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
				$destserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
				$destserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
				
				$destprops = $destserver.Configuration.Properties
				
				foreach ($sourceprop in $sourceserver.Configuration.Properties)
				{
					$displayname = $sourceprop.DisplayName
					
					$destprop = $destprops | where-object{ $_.Displayname -eq $displayname }
					if ($destprop -ne $null)
					{
						try
						{
							$destprop.configvalue = $sourceprop.configvalue
							$destserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
							Write-Output "updated $($destprop.displayname) to $($sourceprop.configvalue)"
						}
						catch { Write-Error "Could not $($destprop.displayname) to $($sourceprop.configvalue). Feature may not be supported." }
					}
				}
				try { $destserver.Configuration.Alter() }
				catch { $needsrestart = $true }
				
				$sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $false
				$sourceserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
				$destserver.Configuration.ShowAdvancedOptions.ConfigValue = $false
				$destserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
				
				if ($needsrestart -eq $true)
				{
					Write-Warning "Some configuration options will be updated once SQL Server is restarted."
				}
				else { Write-Output "Configuration option has been updated." }
			}
			
			If ($Pscmdlet.ShouldProcess($destination, "Removing temp file"))
			{
				Remove-Item $sqlfilename -ErrorAction SilentlyContinue
			}
			
		}
		else
		{
			If ($Pscmdlet.ShouldProcess($destination, "Importing sp_configure from $Path"))
			{	
				$server.Configuration.ShowAdvancedOptions.ConfigValue = $true
				$sql = Get-Content $Path
				foreach ($line in $sql)
				{
					try
					{
						$server.ConnectionContext.ExecuteNonQuery($line) | Out-Null; Write-Output "Successfully executed $line"
					}
					catch
					{
						Write-Error "$line failed. Feature may not be supported."
					}
				}
				$server.Configuration.ShowAdvancedOptions.ConfigValue = $false
				Write-Warning "Some configuration options will be updated once SQL Server is restarted."
			}
		}
	}
	END
	{
		if ($Path.length -gt 0) { 
			$server.ConnectionContext.Disconnect() 
		} else {
			$sourceserver.ConnectionContext.Disconnect() 
			$destserver.ConnectionContext.Disconnect() 
		}
	
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message"))
		{
			Write-Output "SQL Server configuration options migration finished"
		}
	}
}

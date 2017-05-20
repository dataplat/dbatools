function Export-DbaSpConfigure
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

.PARAMETER SqlInstance
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
Export-DbaSpConfigure $sourceserver -Path C:\temp\sp_configure.sql

Exports the SPConfigure on sourceserver to the file C:\temp\sp_configure.sql

.OUTPUTS
File to disk, and string path.

#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance","SqlServer")]
		[object]$SqlInstance,
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
		
        If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) {
            Write-Output "Server configuration export finished"
        }
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Export-SqlSpConfigure
	}
}
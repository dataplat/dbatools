Function Get-DbaServerList
{
<#
.SYNOPSIS 


.DESCRIPTION


.NOTES
Tags: Inventory
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaServerList

.EXAMPLE
Get-DbaServerList

.EXAMPLE   
Get-DbaServerList 
Shows stuff
	
#>
	BEGIN
	{
		Function Get-ConfigFileName
		{
			$docs = [Environment]::GetFolderPath("MyDocuments")
			$folder = "$docs\WindowsPowerShell\Modules\dbareports"
			$configfile = "$folder\dbareports-config.json"
			$exists = Test-Path $configfile
			
			if ($exists -eq $true)
			{
				return $configfile
			}
			else
			{
				$folderexists = Test-Path $folder
				
				if ($folderexists -eq $false)
				{
					$null = New-Item -ItemType Directory $folder -Force -ErrorAction Ignore
				}
				return $configfile
			}
		}
		
		Function Get-Config
		{
			$config = Get-Content -Raw -Path (Get-ConfigFileName) -ErrorAction SilentlyContinue | ConvertFrom-Json
			
			if ($config.SqlServer.length -eq 0)
			{
				throw "No config file found. Have you installed dbareports? Please run Install-DbaReports or Install-DbaReportsClient"
			}
			
			if ($config.username.length -gt 0)
			{
				$username = $config.Username
				$password = $config.SecurePassword | ConvertTo-SecureString
				$tempcred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, $password
				Set-Variable -Name SqlCredential -Value $tempcred -Scope Script
			}
			
			Set-Variable -Name SqlServer -Value $config.sqlserver -Scope Script
			Set-Variable -Name InstallDatabase -Value $config.InstallDatabase -Scope Script
		}
	}
	process
	{
		$SqlServer = $script:SqlServer
		$InstallDatabase = $script:InstallDatabase
		$SqlCredential = $script:SqlCredential
		$configfile = Get-ConfigFileName
		
		if ($SqlServer.length -eq 0)
		{
			throw "No config file found. Have you installed dbareports? Please run Install-DbaReports or Install-DbaReportsClient"
		}
		
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
		
		$logintype = "Windows Authentication"
		$username = "$env:USERDOMAIN\$env:USERNAME"
		
		if ($SqlCredential.Username.Length -gt 0)
		{
			$username = $SqlCredential.UserName.TrimStart("\\")
			
			if ($username -notmatch "\\")
			{
				$logintype = "SQL Authentication"
			}
		}
		
		$execaccount = $sourceserver.JobServer.ServiceAccount
		$samplejob = $sourceserver.JobServer.Jobs | Where-Object { $_.Name -like "*dbareports - *" } | Select-Object -First 1
		$proxy = $samplejob.JobSteps[0].ProxyName
		
		if ($proxy.length -ne 0)
		{
			$proxydetails = $sourceserver.JobServer.ProxyAccounts[$proxy]
			$proxycredential = $proxydetails.CredentialIdentity
			$execaccount = "$proxy ($proxycredential)"
		}
		
		$props = Get-ExtendedProperties
		
		$eppath = $props | Where-Object Name -eq 'dbareports installpath'
		$eplogpath = $props | Where-Object Name -eq 'dbareports logfilefolder'
		$epversion = $props | Where-Object Name -eq 'dbareports version'
		
		[PSCustomObject]@{
			SQLServer = $SqlServer
			Username = $username
			LoginType = $logintype
			ConfigFile = $configfile
			DbaReportsVersion = $epversion.value
			InstallDatabase = $InstallDatabase
			AgentAccount = $execaccount
			InstallPath = $eppath.value
			LogPath = $eplogpath.value
		}
	}
}
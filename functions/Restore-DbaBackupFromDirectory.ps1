Function Restore-DbaBackupFromDirectory
{
<# 
.SYNOPSIS 
Restores SQL Server databases from the backup directory structure created by Ola Hallengren's database maintenance scripts. Different structures coming soon.

.DESCRIPTION 
Many SQL Server database administrators use Ola Hallengren's SQL Server Maintenance Solution which can be found at http://ola.hallengren.com
Hallengren uses a predictable backup structure which made it relatively easy to create a script that can restore an entire SQL Server database instance, down to the master database (next version), to a new server. This script is intended to be used in the event that the originating SQL Server becomes unavailable, thus rendering my other SQL restore script (http://goo.gl/QmfQ6s) ineffective.

.PARAMETER SqlInstance
Required. The SQL Server to which you will be restoring the databases.

.PARAMETER Path
Required. The directory that contains the database backups (ex. \\fileserver\share\sqlbackups\SQLSERVERA)

.PARAMETER ReuseSourceFolderStructure
Restore-SqlBackupFromDirectory will restore to the default user data and log directories, unless this switch is used. Useful if you're restoring from a server that had a complex db file structure.

.PARAMETER Databases
Migrates ONLY specified databases. This list is auto-populated for tab completion.

.PARAMETER Exclude
Excludes specified databases from migration. This list is auto-populated for tab completion.

.PARAMETER Force
Will overwrite any existing databases on $SqlInstance. 

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$cred = Get-Credential, this pass this $cred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER NoRecovery
Leaves the databases in No Recovery state to enable further backups to be added

.NOTES
Tags: DisasterRecovery, Backup, Restore
Author  : Chrissy LeMaire, netnerds.net
Requires: sysadmin access on destination SQL Server.

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.


.LINK 
https://dbatools.io/Restore-SqlBackupFromDirectory

.EXAMPLE   
Restore-SqlBackupFromDirectory -SqlInstance sqlcluster -Path \\fileserver\share\sqlbackups\SQLSERVER2014A

Description

All user databases contained within \\fileserver\share\sqlbackups\SQLSERVERA will be restored to sqlcluster, down the most recent full/differential/logs.

#>	
	#Requires -Version 3.0
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlServer")]
		[DbaInstanceParameter]$SqlInstance,
		[parameter(Mandatory = $true)]
		[string]$Path,
		[switch]$NoRecovery,
		[Alias("ReuseFolderStructure")]
		[switch]$ReuseSourceFolderStructure,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential = [System.Management.Automation.PSCredential]::Empty,
		[switch]$Force
		
	)
	
	DynamicParam
	{
		
		if ($Path)
		{
			$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
			$paramattributes = New-Object System.Management.Automation.ParameterAttribute
			$paramattributes.ParameterSetName = "__AllParameterSets"
			$paramattributes.Mandatory = $false
			$systemdbs = @("master", "msdb", "model", "SSIS")
			$dblist = (Get-ChildItem -Path $Path -Directory).Name | Where-Object { $systemdbs -notcontains $_ }
			$argumentlist = @()
			
			foreach ($db in $dblist)
			{
				$argumentlist += [Regex]::Escape($db)
			}
			
			$validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $argumentlist
			$combinedattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
			$combinedattributes.Add($paramattributes)
			$combinedattributes.Add($validationset)
			$Databases = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Databases", [String[]], $combinedattributes)
			$Exclude = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Exclude", [String[]], $combinedattributes)
			$newparams.Add("Databases", $Databases)
			$newparams.Add("Exclude", $Exclude)
			return $newparams
		}
	}
	
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Restore-SqlBackupFromDirectory -CustomMessage "Restore-DbaDatabase works way better. Please use that instead."
	}
}

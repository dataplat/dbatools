function Copy-SqlDatabaseMail {
    <#
.SYNOPSIS
Migrates Mail Profiles, Accounts, Mail Servers and Mail Server Configs from one SQL Server to another.

.DESCRIPTION
By default, all mail configurations for Profiles, Accounts, Mail Servers and Configs are copied.

The -Profiles parameter is autopopulated for command-line completion and can be used to copy only specific mail profiles.
The -Accounts parameter is autopopulated for command-line completion and can be used to copy only specific mail accounts.
The -mailServers parameter is autopopulated for command-line completion and can be used to copy only specific mail servers.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

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

.PARAMETER Type
Specifies the object type to migrate. Valid options are Job, Alert and Operator. When CategoryType is specified, all categories from the selected type will be migrated. For granular migrations, use the three parameters below.

.PARAMETER Profiles
This parameter is autopopulated for command-line completion and can be used to copy only specific mail profiles.

.PARAMETER Accounts
This parameter is autopopulated for command-line completion and can be used to copy only specific mail accounts.

.PARAMETER mailServers
The parameter is autopopulated for command-line completion and can be used to copy only specific mail servers.

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER Force
Drops and recreates the object if it exists

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Migration
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlDatabaseMail

.EXAMPLE
Copy-SqlDatabaseMail -Source sqlserver2014a -Destination sqlcluster

Copies all database mail objects from sqlserver2014a to sqlcluster, using Windows credentials. If database mail objects with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE
Copy-SqlDatabaseMail -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

Copies all database mail objects from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

.EXAMPLE
Copy-SqlDatabaseMail -Source sqlserver2014a -Destination sqlcluster -WhatIf

Shows what would happen if the command were executed.
#>
	[cmdletbinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[Parameter(ParameterSetName = 'SpecifcTypes')]
		[ValidateSet('ConfigurationValues', 'Profiles', 'Accounts', 'mailServers')]
		[string[]]$Type,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[switch]$Force,
		[switch]$Silent
	)
	
	DynamicParam {
		if ($source) {
			return (Get-ParamSqlDatabaseMail -SqlServer $Source -SqlCredential $SourceSqlCredential)
		}
	}
	
	begin {
		
		function Copy-SqlDatabaseMailConfig {
			[cmdletbinding(SupportsShouldProcess = $true)]
			param ()
			
			Write-Message -Message "Migrating mail server configuration values" -Level Verbose
			$copyMailConfigStatus = [pscustomobject]@{
				SourceServer = $sourceServer
				DestinationServer = $destServer
				Name = "Mail Configuration"
				Type = "Configuration"
				Status = $null
				DateTime = [sqlcollective.dbatools.Utility.DbaDateTime](Get-Date)
			}
			if ($pscmdlet.ShouldProcess($destination, "Migrating all mail server configuration values")) {
				try {
					$sql = $mail.ConfigurationValues.Script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
					Write-Message -Message $sql -Level Debug
					$destServer.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
					$mail.ConfigurationValues.Refresh()
					$copyMailConfigStatus.Status = "Successful"
				}
				catch {
					$copyMailConfigStatus.Status = "Failed"
					$copyMailConfigStatus
					Stop-Function -Message "Unable to migrate mail configuration" -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer -Silent $Silent
				}
			}
			$copyMailConfigStatus
		}
		
		function Copy-SqlDatabaseAccount {
			$sourceAccounts = $sourceServer.Mail.Accounts
			$destAccounts = $destServer.Mail.Accounts
			
			Write-Message -Message "Migrating accounts" -Level Verbose
			foreach ($account in $sourceAccounts) {
				$accountName = $account.name
				$copyMailAccountStatus = [pscustomobject]@{
					SourceServer = $sourceServer
					DestinationServer = $destServer
					Name = $accountName
					Type = "Mail Account"
					Status = $null
					DateTime = [sqlcollective.dbatools.Utility.DbaDateTime](Get-Date)
				}
				
				if ($accounts.count -gt 0 -and $accounts -notcontains $accountName) {
					Stop-Function -Message "No matching accounts found" -Continue -Silent $Silent
				}
				
				if ($destAccounts.name -contains $accountName) {
					if ($force -eq $false) {
						$copyMailAccountStatus.Status = "Skipped"
						$copyMailAccountStatus
						Stop-Function -Message "Account $accountName exists at destination. Use -Force to drop and migrate." -Continue -Silent $Silent
					}
					
					If ($pscmdlet.ShouldProcess($destination, "Dropping account $accountName and recreating")) {
						try {
							Write-Message -Message "Dropping account $accountName" -Level Verbose
							$destServer.Mail.Accounts[$accountName].Drop()
							$destServer.Mail.Accounts.Refresh()
						}
						catch {
							$copyMailAccountStatus.Status = "Failed"
							$copyMailAccountStatus
							Stop-Function -Message "Issue dropping account" -Target $accountName -InnerErrorRecord $_ -Continue -Silent $Silent
						}
					}
				}
				
				if ($pscmdlet.ShouldProcess($destination, "Migrating account $accountName")) {
					try {
						Write-Message -Message "Copying mail account $accountName" -Level Verbose
						$sql = $account.Script() | Out-String
						$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
						Write-Message -Message $sql -Level Debug
						$destServer.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
						$copyMailAccountStatus.Status = "Successful"
					}
					catch {
						$copyMailAccountStatus.Status = "Failed"
						$copyMailAccountStatus
						Stop-Function -Message "Issue copying mail account" -Target $accountName -InnerErrorRecord $_ -Silent $Silent
					}
				}
				$copyMailAccountStatus
			}
		}
		
		function Copy-SqlDatabaseMailProfile {
			
			$sourceProfiles = $sourceServer.Mail.Profiles
			$destProfiles = $destServer.Mail.Profiles
			
			Write-Message -Message "Migrating mail profiles" -Level Verbose
			foreach ($profile in $sourceProfiles) {
				
				$profileName = $profile.name
				$copyMailProfileStatus = [pscustomobject]@{
					SourceServer = $sourceServer
					DestinationServer = $destServer
					Name = $profileName
					Type = "Mail Profile"
					Status = $null
					DateTime = [sqlcollective.dbatools.Utility.DbaDateTime](Get-Date)
				}
				
				if ($profiles.count -gt 0 -and $profiles -notcontains $profileName) {
					Stop-Function -Message "No matching profiles found" -Continue -Silent $Silent
				}
				
				if ($destProfiles.name -contains $profileName) {
					if ($force -eq $false) {
						$copyMailProfileStatus.Status = "Skipped"
						$copyMailProfileStatus
						Stop-Function -Message "Profile $profileName exists at destination. Use -Force to drop and migrate." -Continue -Silent $Silent
					}
					
					If ($pscmdlet.ShouldProcess($destination, "Dropping profile $profileName and recreating")) {
						try {
							Write-Message -Message "Dropping profile $profileName" -Level Verbose
							$destServer.Mail.Profiles[$profileName].Drop()
							$destServer.Mail.Profiles.Refresh()
						}
						catch {
							$copyMailProfileStatus.Status = "Failed"
							$copyMailProfileStatus
							Stop-Function -Message "Issue dropping profile" -Target $profileName -InnerErrorRecord $_ -Continue -Silent $Silent
						}
					}
				}
				
				if ($pscmdlet.ShouldProcess($destination, "Migrating mail profile $profileName")) {
					try {
						Write-Message -Message "Copying mail profile $profileName" -Level Verbose
						$sql = $profile.Script() | Out-String
						$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
						Write-Message -Message $sql -Level Debug
						$destServer.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
						$destServer.Mail.Profiles.Refresh()
						$copyMailProfileStatus.Status = "Successful"
					}
					catch {
						$copyMailProfileStatus.Status = "Failed"
						$copyMailProfileStatus
						Stop-Function -Message "Issue copying mail profile" -Target $profileName -InnerErrorRecord $_ -Silent $Silent
					}
				}
				$copyMailProfileStatus
			}
		}
		
		function Copy-SqlDatabasemailServer {
			$sourceMailServers = $sourceServer.Mail.Accounts.mailServers
			$destMailServers = $destServer.Mail.Accounts.mailServers
			
			Write-Message -Message "Migrating mail servers" -Level Verbose
			foreach ($mailServer in $sourceMailServers) {
				$mailServerName = $mailServer.name
				$copyMailServerStatus = [pscustomobject]@{
					SourceServer = $sourceServer
					DestinationServer = $destServer
					Name = $mailServerName
					Type = "Mail Server"
					Status = $null
					DateTime = [sqlcollective.dbatools.Utility.DbaDateTime](Get-Date)
				}
				if ($mailServers.count -gt 0 -and $mailServers -notcontains $mailServerName) {
					Stop-Function -Message "No data found" -Continue -Silent $Silent
				}
				
				if ($destMailServers.name -contains $mailServerName) {
					if ($force -eq $false) {
						$copyMailServerStatus.Status = "Skipped"
						$copyMailServerStatus
						Stop-Function -Message "Mail server $mailServerName exists at destination. Use -Force to drop and migrate." -Target $mailServerName -Silent $Silent -Continue
					}
					
					If ($pscmdlet.ShouldProcess($destination, "Dropping mail server $mailServerName and recreating")) {
						try {
							Write-Message -Message "Dropping mail server $mailServerName" -Level Verbose
							$destServer.Mail.Accounts.mailServers[$mailServerName].Drop()
						}
						catch {
							$copyMailServerStatus.Status = "Failed"
							$copyMailServerStatus
							Stop-Function -Message "Issue dropping mail server" -Target $mailServerName -InnerErrorRecord $_ -Continue -Silent $Silent
						}
					}
				}
				
				if ($pscmdlet.ShouldProcess($destination, "Migrating account mail server $mailServerName")) {
					try {
						Write-Message -Message "Copying mail server $mailServerName" -Level Verbose
						$sql = $mailServer.Script() | Out-String
						$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
						Write-Message -Message $sql -Level Debug
						$destServer.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
						$copyMailServerStatus.Status = "Successful"
					}
					catch {
						$copyMailServerStatus.Status = "Failed"
						$copyMailServerStatus
						Stop-Function -Message "Issue copying mail server" -Target $mailServerName -InnerErrorRecord $_ -Silent $Silent
					}
				}
			}
		}
		
		$sourceServer = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceServer.DomainInstanceName
		$destination = $destServer.DomainInstanceName
		
		
		if ($sourceServer.versionMajor -lt 9 -or $destServer.versionMajor -lt 9) {
			Stop-Function -Message "Database Mail is only supported in SQL Server 2005 and above. Quitting." -Silent $Silent
		}
		
		$mail = $sourceServer.mail
	}
	process {
		
		if ($type.count -gt 0) {
			
			switch ($type) {
				"ConfigurationValues" {
					Copy-SqlDatabaseMailConfig
					$destServer.Mail.ConfigurationValues.Refresh()
				}
				
				"Profiles" {
					Copy-SqlDatabaseMailProfile
					$destServer.Mail.Profiles.Refresh()
				}
				
				"Accounts" {
					Copy-SqlDatabaseAccount
					$destServer.Mail.Accounts.Refresh()
				}
				
				"mailServers" {
					Copy-SqlDatabasemailServer
				}
			}
			
			return
		}
		
		
		$profiles = $psboundparameters.Profiles
		$accounts = $psboundparameters.Accounts
		$mailServers = $psboundparameters.mailServers
		
		if (($profiles.count + $accounts.count + $mailServers.count) -gt 0) {
			
			if ($profiles.count -gt 0) {
				Copy-SqlDatabaseMailProfile -Profiles $profiles
				$destServer.Mail.Profiles.Refresh()
			}
			
			if ($accounts.count -gt 0) {
				Copy-SqlDatabaseAccount -Accounts $accounts
				$destServer.Mail.Accounts.Refresh()
			}
			
			if ($mailServers.count -gt 0) {
				Copy-SqlDatabasemailServer -mailServers $mailServers
			}
			
			return
		}
		
		Copy-SqlDatabaseMailConfig
		$destServer.Mail.ConfigurationValues.Refresh()
		Copy-SqlDatabaseAccount
		$destServer.Mail.Accounts.Refresh()
		Copy-SqlDatabaseMailProfile
		$destServer.Mail.Profiles.Refresh()
		Copy-SqlDatabasemailServer
		$copyMailConfigStatus
		$copyMailAccountStatus
		$copyMailProfileStatus
		$copyMailServerStatus
		$enableDBMailStatus
		
        <# ToDo: Use Get/Set-DbaSpConfigure once the dynamic parameters are replaced. #>
		
		$sourceDbMailEnabled = ($sourceServer.Configuration.DatabaseMailEnabled).ConfigValue
		Write-Message -Message "$sourceServer DBMail configuration value: $sourceDbMailEnabled" -Level Verbose
		
		$destDbMailEnabled = ($destServer.Configuration.DatabaseMailEnabled).ConfigValue
		Write-Message -Message "$destServer DBMail configuration value: $destDbMailEnabled" -Level Verbose
		$enableDBMailStatus = [pscustomobject]@{
			SourceServer = $sourceServer.name
			DestinationServer = $destServer.name
			Name = "Enabled DBMail on Destination"
			Type = "Configuration"
			Status = if ($destDbMailEnabled -eq 1) { "Enabled" } else { $null }
			DateTime = [sqlcollective.dbatools.Utility.DbaDateTime](Get-Date)
		}
		
		if (($sourceDbMailEnabled -eq 1) -and ($destDbMailEnabled -eq 0)) {
			if ($pscmdlet.ShouldProcess($destination, "Enabling Database Mail")) {
				try {
					Write-Message -Message "Enabling Database Mail on $destServer" -Level Verbose
					$destServer.Configuration.DatabaseMailEnabled.ConfigValue = 1
					$destServer.Alter()
					$enableDBMailStatus.Status = "Successful"
				}
				catch {
					Stop-Function -Message "Cannot enable Database Mail" -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer -Silent $Silent
					$enableDBMailStatus.Status = "Failed"
				}
			}
		}
	}
}

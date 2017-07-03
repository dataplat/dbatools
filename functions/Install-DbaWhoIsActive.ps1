function Install-DbaWhoIsActive {
<#
	.SYNOPSIS
		Automatically installs or updates sp_WhoisActive by Adam Machanic.
	
	.DESCRIPTION
		This command downloads, extracts and installs sp_WhoisActive with Adam's permission. To read more about sp_WhoisActive, please visit:
		
		Updates: http://sqlblog.com/blogs/adam_machanic/archive/tags/who+is+active/default.aspx
		
		Also, consider donating to Adam if you find this stored procedure helpful: http://tinyurl.com/WhoIsActiveDonate
		
		Note that you will be prompted a bunch of times to confirm an action. To disable this behavior, pass the -Confirm:$false parameter (see example below).
	
	.PARAMETER SqlInstance
		The SQL Server instance.You must have sysadmin access and server version must be SQL Server version 2000 or higher.
	
	.PARAMETER SqlCredential
		Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
		
		$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
		
		Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.
	
	.PARAMETER Database
		The database to install the procedures to.
		This parameter is mandatory when executing this command unattendedly.
	
	.PARAMETER Silent
		Replaces user friendly yellow warnings with bloody red exceptions of doom!
		Use this if you want the function to throw terminating errors you want to catch.
	
	.PARAMETER WhatIf
		Shows what would happen if the command were to run. No actions are actually performed.
	
	.PARAMETER Confirm
		Prompts you for confirmation before executing any changing operations within the command.
	
	.EXAMPLE
		Install-DbaWhoIsActive -SqlInstance sqlserver2014a -Database master
		
		Installs sp_WhoisActive to sqlserver2014a's master database. Logs in using Windows Authentication.
	
	.EXAMPLE
		Install-DbaWhoIsActive -SqlInstance sqlserver2014a -SqlCredential $cred -Confirm:$false
		
		Pops up a dialog box asking which database on sqlserver2014a you want to install the proc to. Logs into SQL Server using SQL Authentication.
		
		Does not prompt multiple times.
	
	.EXAMPLE
		$instances = Get-DbaRegisteredServerName sqlserver
		Install-DbaWhoIsActive -SqlInstance $instances -Database master
		
		This command doesn't support passing both servers and default database, but you can accomplish the same thing by passing an array and specifying a database.
	
	.NOTES
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
		https://dbatools.io/Install-DbaWhoIsActive
#>
	
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]
		$SqlInstance,
		
		[PsCredential]
		$SqlCredential,
		
		[object]
		$Database,
		
		[switch]
		$Silent
	)
	
	begin {
		
		$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
		$sqlfile = (Get-ChildItem "$temp\who*active*.sql" | Select-Object -First 1).FullName
		
		if ($sqlfile) {
			Write-Message -Level Output -Message "Found $sqlfile"
		}
		else {
			Write-Message -Level Verbose -Message "No $sqlfile found, downloading"
			
			if ($PSCmdlet.ShouldProcess($env:computername, "Downloading sp_WhoisActive")) {
				try {
					Write-Message -Level Output -Message "Downloading sp_WhoisActive zip file, unzipping and installing."
					
					$url = 'http://whoisactive.com/who_is_active_v11_17.zip'
					$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
					$zipfile = "$temp\spwhoisactive.zip"
					
					try {
						Invoke-WebRequest $url -OutFile $zipfile -ErrorAction Stop
					}
					catch {
						#try with default proxy and usersettings
						(New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
						Invoke-WebRequest $url -OutFile $zipfile -ErrorAction Stop
					}
					
					# Unblock if there's a block
					Unblock-File $zipfile -ErrorAction SilentlyContinue
					
					# Keep it backwards compatible
					$shell = New-Object -ComObject Shell.Application
					$zipPackage = $shell.NameSpace($zipfile)
					$destinationFolder = $shell.NameSpace($temp)
					$destinationFolder.CopyHere($zipPackage.Items())
					
					Remove-Item -Path $zipfile
					
					$sqlfile = (Get-ChildItem "$temp\who*active*.sql" | Select-Object -First 1).Name
					$sqlfile = "$temp\$sqlfile"
				}
				catch {
					Stop-Function -Message "Couldn't download sp_WhoisActive. Please download and install manually from http://whoisactive.com/who_is_active_v11_17.zip." -ErrorRecord $_
					return
				}
			}
		}
		
		if ($PSCmdlet.ShouldProcess($env:computername, "Reading SQL file into memory")) {
			Write-Message -Level Output -Message "Using $sqlfile"
			
			$sql = [IO.File]::ReadAllText($sqlfile)
			$sql = $sql -replace 'USE master', ''
			$batches = $sql -split "GO\r\n"
		}
	}
	
	process {
		if (Test-FunctionInterrupt) { return }
		
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			if (-not $Database) {
				if ($PSCmdlet.ShouldProcess($instance, "Prompting with GUI list of databases")) {
					$Database = Show-SqlDatabaseList -SqlServer $server -Title "Install sp_WhoisActive" -Header "To deploy sp_WhoisActive, select a database or hit cancel to quit." -DefaultDb "master"
					
					if (-not $Database) {
						Stop-Function -Message "You must select a database to install the procedure" -Target $Database
						return
					}
					
					if ($Database -ne 'master') {
						Write-Message -Level Warning -Message "You have selected a database other than master. When you run Show-SqlWhoIsActive in the future, you must specify -Database $Database"
					}
				}
			}
			
			if ($PSCmdlet.ShouldProcess($instance, "Installing sp_WhoisActive")) {
				foreach ($batch in $batches) {
					try {
						$null = $server.databases[$Database].ExecuteNonQuery($batch)
					}
					catch {
						Stop-Function -Message "Failed to install stored procedure." -ErrorRecord $_ -Continue -Target $instance
					}
				}
				
				Write-Message -Level Output -Message "Finished installing/updating sp_WhoisActive in $Database on $instance"
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Install-SqlWhoIsActive
	}
}
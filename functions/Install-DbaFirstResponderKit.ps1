Function Install-DbaFirstResponderKit {
<#
.SYNOPSIS
Installs or updates the First Responder Kit stored procedures.

.DESCRIPTION
Downloads, extracts and installs the First Responder Kit stored procedures: 
sp_Blitz, sp_BlitzWho, sp_BlitzFirst, sp_BlitzIndex, sp_BlitzCache and sp_BlitzTrace. 

First Responder Kit links:
http://FirstResponderKit.org
https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit

.PARAMETER SqlInstance
SQL Server instance or collection of SQL Server instances

.PARAMETER Database
Database to store the FRK stored procs, typically master and master by default

.PARAMETER SqlCredential
Use SqlCredential to connect to SqlInstance with SQL authentication. 
If SqlCredential is not specified, Windows authentication will be used.

.NOTES 
Original author: Tara Kizer, Brent Ozar Unlimited (https://www.brentozar.com/)
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Install-DbaFirstResponderKit

.EXAMPLE
Install-DbaFirstResponderKit -SqlInstance server1 -Database master

Logs into server1 with Windows authentication and then installs the FRK in the master database.

.EXAMPLE
Install-DbaFirstResponderKit -SqlInstance server1\instance1 -Database DBA

Logs into server1\instance1 with Windows authentication and then installs the FRK in the DBA database.

.EXAMPLE
Install-DbaFirstResponderKit -SqlInstance server1\instance1 -Database master -SqlCredential $cred

Logs into server1\instance1 with SQL authentication and then installs the FRK in the master database.

#>
	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[object]$Database = "master",
		[switch]$Silent
	)
	
	begin {
		$url = 'https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/archive/master.zip'
		$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
		$zipfile = "$temp\SQL-Server-First-Responder-Kit-master.zip"
		$zipfolder = "$temp\SQL-Server-First-Responder-Kit-master\"
		
		if ($zipfile | Test-Path) {
			Remove-Item -Path $zipfile -ErrorAction SilentlyContinue
		}
		
		if ($zipfolder | Test-Path) {
			Remove-Item -Path $zipfolder -Recurse -ErrorAction SilentlyContinue
		}
		
		$null = New-Item -ItemType Directory -Path $zipfolder -ErrorAction SilentlyContinue
		
		Write-Message -Level Verbose -Message "Downloading and unzipping the First Responder Kit zip file."
		
		try {
			try {
				Invoke-WebRequest $url -OutFile $zipfile
			}
			catch {
				# Try with default proxy and usersettings
				(New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
				Invoke-WebRequest $url -OutFile $zipfile
			}
			
			# Unblock if there's a block
			Unblock-File $zipfile -ErrorAction SilentlyContinue
			
			# Unzip the files
			$shell = New-Object -ComObject Shell.Application
			$zip = $shell.NameSpace($zipfile)
			
			foreach ($item in $zip.items()) {
				$shell.Namespace($temp).CopyHere($item)
			}
			
			Remove-Item -Path $zipfile
		}
		catch {
			Stop-Function -Message "Couldn't download the First Responder Kit. Download and install manually from https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/archive/master.zip." -ErrorRecord $_
			return
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
				Stop-Function -Message "Failed to connect to: $instance" -Target $instance -ErrorRecord $_ -Continue
			}
			
			Write-Message -Level Output -Message "Starting installing/updating the First Responder Kit stored procedures in $database on $instance."
			
			# Install/Update each FRK stored procedure
			Get-ChildItem $zipfolder -Filter sp_Blitz*.sql | Foreach-Object {
				if ($_.Name -ne "sp_BlitzRS.sql") {
					Write-Message -Level Output -Message "Installing/Updating $_"
					$sql = [IO.File]::ReadAllText($_.FullName)
					
					foreach ($query in ($sql -Split "\nGO\b")) {
						$query = $query.Trim()
						if ($query) {
							try {
								$null = $server.Query($query, $Database)
							}
							catch {
								Write-Message -Level Warning -Message "Could not execute at least one portion of $($_.Name)"
							}
						}
					}
				}
			}
			Write-Message -Level Output -Message "Finished installing/updating the First Responder Kit stored procedures in $database on $instance."
		}
	}
}
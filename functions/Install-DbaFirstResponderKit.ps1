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
Database to store the FRK stored procs, typically master

.PARAMETER SqlCredential
Use SqlCredential to connect to SqlInstance with SQL authentication. 
If SqlCredential is not specified, Windows authentication will be used.

.NOTES 
Original author: Tara Kizer, Brent Ozar Unlimited (https://www.brentozar.com/)
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
		[Parameter(Mandatory = $True, ValueFromPipeline = $True)]
		#[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlInstance,
		[object]$Database,
		[object]$SqlCredential
	)
	
	BEGIN {
		$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
		$zipfile = "$temp\SQL-Server-First-Responder-Kit-master.zip"
		$zipfolder = "$temp\SQL-Server-First-Responder-Kit-master\"
		
		$url = 'https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/archive/master.zip'
		
		if ($zipfile | Test-Path) {
			Remove-Item -Path $zipfile
		}
		
		if ($zipfolder | Test-Path) {
			Remove-Item -Path $zipfolder -Recurse
		}
		
		Write-Host "Downloading and unzipping the First Responder Kit zip file."
		
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
	
	PROCESS {
		Foreach ($instance in $SqlInstance) {
			try {
				Write-Host "Connecting to $instance"
				$Connection = Connect-DbaSqlServer -SqlInstance $instance -Credential $sqlcredential
			}
			catch {
				Write-Host "Failed to connect to $instance : $($_.Exception.Message)"
			}
			
			# Install/Update each FRK stored procedure
			Get-ChildItem $zipfolder -Filter sp_Blitz*.sql | Foreach-Object {
				if ($_.Name -ne "sp_BlitzRS.sql") {
					Write-Host "Installing/Updating $_."
					
					$sql = [IO.File]::ReadAllText($_.FullName)
					
					$null = $Connection.databases[$Database].ExecuteNonQuery($sql)
				}
			}
			
			Write-Host "Finished installing/updating the First Responder Kit stored procedures in $database on $instance."
		}
	}
	END { }
}

Function Install-SqlWhoIsActive
{
<#
.SYNOPSIS
Automatically installs or updates sp_WhoIsActive by Adam Machanic.

.DESCRIPTION
This command downloads, extracts and installs sp_whoisactive with Adam's permission. To read more about sp_WhoIsActive, please visit:

Updates: http://sqlblog.com/blogs/adam_machanic/archive/tags/who+is+active/default.aspx

Also, consider donating to Adam if you find this stored procedure helpful: http://tinyurl.com/WhoIsActiveDonate

.PARAMETER SqlServer
The SQL Server instance.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER OutputDatabaseName
Outputs just the database name instead of the success message

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
https://dbatools.io/Install-SqlWhoIsActive

.EXAMPLE
Install-SqlWhoIsActive -SqlServer sqlserver2014a -Database master

Installs sp_WhoIsActive to sqlserver2014a's master database. Logs in using Windows Authentication.
	
.EXAMPLE   
Install-SqlWhoIsActive -SqlServer sqlserver2014a -SqlCredential $cred

Pops up a dialog box asking which database on sqlserver2014a you want to install the proc to. Logs into SQL Server using SQL Authentication.
	

.EXAMPLE 
$servers = Get-SqlRegisteredServerName sqlserver
Install-SqlWhoIsActive -SqlServer $servers -Database master

This command doesn't support passing both servers and default database, but you can accomplish the same thing by passing an array and specifying a database.

#>
	
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[object]$SqlCredential,
		[switch]$OutputDatabaseName
	)
	
	DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabase -SqlServer $sqlserver[0] -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		Function Get-SpWhoIsActive
		{
			
			$url = 'http://sqlblog.com/files/folders/42453/download.aspx'
			$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
			$zipfile = "$temp\spwhoisactive.zip"
			
			try
			{
				Invoke-WebRequest $url -OutFile $zipfile
			}
			catch
			{
				#try with default proxy and usersettings
				(New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
				Invoke-WebRequest $url -OutFile $zipfile
			}
			
			# Unblock if there's a block
			Unblock-File $zipfile -ErrorAction SilentlyContinue
			
			# Keep it backwards compatible
			$shell = New-Object -COM Shell.Application
			$zipPackage = $shell.NameSpace($zipfile)
			$destinationFolder = $shell.NameSpace($temp)
			$destinationFolder.CopyHere($zipPackage.Items())
			
			Remove-Item -Path $zipfile
		}
	}
	
	PROCESS
	{
		# Used a dynamic parameter? Convert from RuntimeDefinedParameter object to regular array
		$Database = $psboundparameters.Database
		
		foreach ($server in $sqlserver)
		{
			# please continue to use these variable names for consistency
			$sourceserver = Connect-SqlServer -SqlServer $server -SqlCredential $SqlCredential
			$source = $sourceserver.DomainInstanceName
			
			if ($database.length -eq 0)
			{
				$database = Show-SqlDatabaseList -SqlServer $sourceserver -Title "Install sp_WhoisActive" -Header "sp_WhoIsActive not found. To deploy, select a database or hit cancel to quit." -DefaultDb "master"
				
				if ($database.length -eq 0)
				{
					throw "You must select a database to install the procedure"
				}
				
				if ($database -ne 'master')
				{
					Write-Warning "You have selected a database other than master. When you run Show-SqlWhoIsActive in the future, you must specify -Database $database"
				}
			}
			
			$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
			$sqlfile = (Get-ChildItem "$temp\who*active*.sql" | Select-Object -First 1).FullName
			
			if ($sqlfile.Length -eq 0)
			{
				try
				{
					Write-Output "Downloading sp_WhoIsActive zip file, unzipping and installing."
					Get-SpWhoIsActive
				}
				catch
				{
					throw "Couldn't download sp_WhoIsActive. Please download and install manually from http://sqlblog.com/files/folders/42453/download.aspx."
				}
			}
			
			$sqlfile = (Get-ChildItem "$temp\who*active*.sql" | Select-Object -First 1).Name
			$sqlfile = "$temp\$sqlfile"
			
			$sql = [IO.File]::ReadAllText($sqlfile)
			$sql = $sql -replace 'USE master', ''
			$batches = $sql -split "GO\r\n"
			
			foreach ($batch in $batches)
			{
				try
				{
					$null = $sourceserver.databases[$database].ExecuteNonQuery($batch)
					
				}
				catch
				{
					Write-Exception $_
					throw "Can't install stored procedure. See exception text for details."
				}
			}
			
			if ($OutputDatabaseName -eq $true)
			{
				return $database
			}
			else
			{
				Write-Output "Finished installing/updating sp_WhoIsActive in $database on $server"
			}
			
			$sourceserver.ConnectionContext.Disconnect()
		}
	}
	
	END
	{
		# nothin
	}
}
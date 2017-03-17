Function Install-FirstResponderKit
{
<#
.SYNOPSIS
Automatically installs or updates SQL Server First Responder Kit by BrentOzarULTD.

.DESCRIPTION
This command downloads, extracts and installs all scripts included in the SQL Server First Responder Kit with BrentOzarULTD's permission. To read more about SQL Server First Responder Kit, please visit:

Updates: https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit

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
https://dbatools.io/Install-FirstResponderKit

.EXAMPLE
Install-FirstResponderKit -SqlServer sqlserver2014a -Database master

Installs all scripts to sqlserver2014a's master database. Logs in using Windows Authentication.
	
.EXAMPLE   
Install-SqlWhoIsActive -SqlServer sqlserver2014a -SqlCredential $cred

Pops up a dialog box asking which database on sqlserver2014a you want to install the proc to. Logs into SQL Server using SQL Authentication.
	
.EXAMPLE
Install-FirstResponderKit -SqlServer sqlserver2014a -IncludeSSRS

Installs all scripts, including the one specific for the SSRS database. Depends on the SSRS database name to be "ReportServer".
#>
	
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[string]$Path,
		[switch]$OutputDatabaseName,
		[string]$Header = "FirstResponderKit not found. To deploy, select a database or hit cancel to quit.",
		[switch]$Force,
        [switch]$IncludeSSRS
	)
	
	DynamicParam { if ($sqlserver) { return Get-ParamSqlDatabase -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		
		# please continue to use these variable names for consistency
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential -RegularUser
		$source = $sourceserver.DomainInstanceName
		
		Function Get-FirstResponderKit
		{
			
			$url = 'https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/archive/dev.zip'
			$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
			$zipfile = "$temp\FirstResponderKit.zip"
			
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
		
		# Used a dynamic parameter? Convert from RuntimeDefinedParameter object to regular array
		$Database = $psboundparameters.Database
		
		if ($Header -like '*update*')
		{
			$action = "update"
		}
		else
		{
			$action = "install"
		}
		
		$textinfo = (Get-Culture).TextInfo
		$actiontitle = $textinfo.ToTitleCase($action)
		
		if ($action -eq "install")
		{
			$actioning = "installing"
		}
		else
		{
			$actioning = "updating"
		}
	}
	
	PROCESS
	{
		
		if ($database.length -eq 0)
		{
			$database = Show-SqlDatabaseList -SqlServer $sourceserver -Title "$actiontitle FirstResponderKit" -Header $header -DefaultDb "master"
			
			if ($database.length -eq 0)
			{
				throw "You must select a database to $action the procedure"
			}
			
			if ($database -ne 'master')
			{
				Write-Warning "You have selected a database other than master. When you run Show-SqlWhoIsActive in the future, you must specify -Database $database"
			}
		}
		
		if ($Path.Length -eq 0)
		{
			$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
			
            $file = Get-ChildItem "$temp\*responder*\sp_*.sql" | Select -First 1
			$path = $file.FullName
			
			if ($path.Length -eq 0 -or $force -eq $true)
			{
				try
				{
					if ($OutputDatabaseName -eq $false)
					{
						Write-Output "Downloading FirstResponderKit zip file, unzipping and $actioning."
					}
					
					Get-FirstResponderKit
				}
				catch
				{
					throw "Couldn't download sp_WhoIsActive. Please download and $action manually from http://sqlblog.com/files/folders/42453/download.aspx."
				}
			}
            
			$path = (Get-ChildItem "$temp\*responder*\sp_*.sql" | Select -First 1).FullName
		}
		
		if ((Test-Path $Path) -eq $false)
		{
			throw "Invalid path at $path"	
		}

        foreach($file in Get-ChildItem "$temp\*responder*\sp_*.sql")
        {
            $path = $file.FullName

            if(($path.Contains("sp_BlitzRS")) -and ($IncludeSSRS -eq $false))
            {
                continue
            }

            $sql = [IO.File]::ReadAllText($path)
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
				    throw "Can't $action stored procedure. See exception text for details."
			    }
		    }
        }
	}
	
	END
	{
        $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
        $directory = Get-ChildItem "$temp\*responder*" | Select -First 1

        write-host $directory.FullName;

        if([string]::IsNullOrEmpty($directory) -ne $true)
        {
            Remove-Item $directory -Recurse -ErrorAction Ignore
        }

		$sourceserver.ConnectionContext.Disconnect()
		
		if ($OutputDatabaseName -eq $true)
		{
			return $database
		}
		else
		{
			Write-Output "Finished $actioning FirstResponderKit in $database on $SqlServer "
		}
	}
}

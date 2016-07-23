Function Update-SqlWhoIsActive
{
<#
.SYNOPSIS
Automatically updates sp_WhoIsActive by Adam Machanic.

.DESCRIPTION
If -Path is not specified, this command downloads, extracts and updates sp_whoisactive with Adam's permission. 

To read more about sp_WhoIsActive, please visit http://sqlblog.com/blogs/adam_machanic/archive/tags/who+is+active/default.aspx

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
https://dbatools.io/Update-SqlWhoIsActive

.EXAMPLE
Update-SqlWhoIsActive -SqlServer sqlserver2014a -Database master

Updates sp_WhoIsActive to sqlserver2014a's master database. Logs in using Windows Authentication.
	
.EXAMPLE   
Update-SqlWhoIsActive -SqlServer sqlserver2014a -SqlCredential $cred

Pops up a dialog box asking which database on sqlserver2014a you want to install the proc to. Logs into SQL Server using SQL Authentication.
	
#>
	
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[string]$Path,
		[switch]$OutputDatabaseName,
		[string]$Header = "To update, select a database or hit cancel to quit."
	)
	
	DynamicParam { if ($sqlserver) { return Get-ParamSqlDatabase -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	END
	{
		$Database = $psboundparameters.Database
	
		if ($Database.length -eq 0)
		{
			Install-SqlWhoIsActive -SqlServer $sqlserver -SqlCredential $SqlCredential -Path $Path -Header $header
		}
		else
		{
			Install-SqlWhoIsActive -SqlServer $sqlserver -SqlCredential $SqlCredential -Path $Path -Header $header -Database $database
		}
	}
}
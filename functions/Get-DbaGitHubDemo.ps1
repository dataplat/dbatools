Function Get-DbaGitHubDemo
{
<#
.SYNOPSIS 
Simple template

.DESCRIPTION
By default, all SQL Agent categories for Jobs, Operators and Alerts are copied.  

.PARAMETER SqlServer
The SQL Server instance.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.NOTES 
Original Author: You (@YourTwitter, Yourblog.net)

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaGitHubDemo

.EXAMPLE
Get-DbaGitHubDemo -SqlServer sqlserver2014a
Copies all policies and conditions from sqlserver2014a to sqlcluster, using Windows credentials. 

.EXAMPLE   
Get-DbaGitHubDemo -SqlServer sqlserver2014a -SqlCredential $cred
Does this, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

.EXAMPLE   
Get-DbaGitHubDemo -SqlServer sqlserver2014 -WhatIf
Shows what would happen if the command were executed.
	
.EXAMPLE   
Get-DbaGitHubDemo -SqlServer sqlserver2014a -Policy 'xp_cmdshell must be disabled'
Does this 
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[string]$FilePath
	)
	
	
	DynamicParam { if ($sqlserver) { return Get-ParamSqlDatabases -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
		$source = $sourceserver.DomainInstanceName
		
		$Databases = $psboundparameters.Databases
	}
	
	PROCESS
	{
		
		# whatever, one time i made a comment in the real PowerShell
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		
		
	}
}

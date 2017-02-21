FUNCTION Get-DbaSecurityAudit
{
<#
.SYNOPSIS
Gets SQL Security Audit information for each instance(s) of SQL Server.

.DESCRIPTION
 The Get-DbaSecurityAudit command gets SQL Security Audit information for each instance(s) of SQL Server.
	
.PARAMETER SqlInstance
SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input to allow the function
to be executed against multiple SQL Server instances.

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, current Windows login will be used.

.NOTES
Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.LINK
https://dbatools.io/Get-DbaSecurityAudit

.EXAMPLE
Get-DbaSecurityAudit -SqlServer localhost
Returns all Security Audits on the local default SQL Server instance

.EXAMPLE
Get-DbaSecurityAudit -SqlServer localhost, sql2016
Returns all Security Audits for the local and sql2016 SQL Server instances

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	PROCESS
	{
		foreach ($servername in $sqlserver)
        {	
			Write-Verbose "Attempting to connect to $servername"
			try
			{
				$server = Connect-SqlServer -SqlServer $servername -SqlCredential $SqlCredential
			}
			catch
			{
				Write-Warning "Can't connect to $servername or access denied. Skipping."
				continue
			}

            if ($server.versionMajor -lt 10)
            {
                Write-Warning "Server Audits are only supported in SQL Server 2008 and above. Quitting."
                return
            }
			
            $serveraudits = $server.Audits

            foreach ($audit in $serveraudits)
            {
            	[pscustomobject]@{
				Server = $server.name
                Name = $audit.name
                Status = $audit.enabled
                FilePath = $audit.filepath
                FileName = $audit.filename
                }
		    } 
		}
	}
}

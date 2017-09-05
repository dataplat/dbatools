Function Get-DbaPolicy
{
<#
.SYNOPSIS
Returns polices from policy based management from an instance.

.DESCRIPTION
Returns details of policies with the option to filter on Category and SystemObjects.

.PARAMETER SqlInstance
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2008 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Category
Filters results to only show policies in the category selected

.PARAMETER SystemObject
By default system objects are filtered out. Use this parameter to INCLUDE them 

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaPolicy 

.EXAMPLE   
Get-DbaPolicy -SqlInstance CMS

Returns all policies from CMS server

.EXAMPLE   
Get-DbaPolicy -SqlInstance CMS -SqlCredential $cred

Uses a credential $cred to connect and return all policies from CMS instance

.EXAMPLE   
Get-DbaPolicy -SqlInstance CMS -Category MorningCheck

Returns all policies from CMS server that part of the PolicyCategory MorningCheck
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
        [string]$Category,
        [switch]$IncludeSystemObject
	)
	
begin 
{
	try 
    { 
        $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential 
    }
	catch 
    { 
        write-output "failed to connect" 
    }
	
	$sqlconn = $server.ConnectionContext.SqlConnectionObject
	$sqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sqlconn
    
    $filter

}
process
{
	# DMF is the Declarative Management Framework, Policy Based Management's old name
	$store = New-Object Microsoft.SqlServer.Management.DMF.PolicyStore $sqlStoreConnection
	
    if ($Category)
    {
        $store.Policies | Where {$_.PolicyCategory -eq $Category} | select Name, PolicyCategory, Condition, Enabled, HelpLink, HelpText, Description
    }
    else
    {
        if ($IncludeSystemObject)
        {
            $store.Policies | select Name, PolicyCategory, Condition, Enabled, HelpLink, HelpText, Description
        }    
        else
        {
            $store.Policies | Where-Object {$_.IsSystemObject -eq 0 } | select Name, PolicyCategory, Condition, Enabled, HelpLink, HelpText, Description
        }
    }
    
    $server.ConnectionContext.Disconnect()
}
}


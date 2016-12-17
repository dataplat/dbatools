Function Get-DbaTrigger
{
<#
.SYNOPSIS
Get all existing triggers on one or more SQL instances.

.DESCRIPTION
Get all existing triggers on one or more SQL instances.

Default output includes columns ComputerName, SqlInstance, Database, TriggerName, IsEnabled and DateLastMofied.

.PARAMETER SqlInstance
The SQL Instance that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user.

.NOTES
Author: Klaas Vandenberghe ( @PowerDBAKlaas )

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
 https://dbatools.io/Get-DbaTrigger

.EXAMPLE
Get-DbaTrigger -SqlInstance ComputerA\sql987

Returns a custom object displaying ComputerName, SqlInstance, Database, TriggerName, IsEnabled and DateLastMofied.

.EXAMPLE
Get-DbaTrigger -SqlInstance 'ComputerA\sql987','ComputerB'

Returns a custom object displaying ComputerName, SqlInstance, Database, TriggerName, IsEnabled and DateLastMofied from two instances.

.EXAMPLE
Get-DbaTrigger -SqlInstance ComputerA\sql987 | Out-Gridview

Returns a gridview displaying ComputerName, SqlInstance, Database, TriggerName, IsEnabled and DateLastMofied.

.EXAMPLE
'ComputerA\sql987','ComputerB' | Get-DbaTrigger | Out-Gridview

Returns a custom object displaying ComputerName, SqlInstance, Database, TriggerName, IsEnabled and DateLastMofied from two instances.

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer","instance")]
		[string[]]$SqlInstance,
		[PsCredential]$Credential,
		[switch]$Simple
	)

	DynamicParam {
		if ($SqlInstance) {
			return Get-ParamSqlDatabases -SqlServer $SqlInstance[0] -SqlCredential $Credential
		}
	}

	BEGIN {}

    PROCESS {
        foreach ($Instance in $SqlInstance)
            {
            Write-Verbose "Connecting to $Instance"
		    try
		        {
			    $server = Connect-SqlServer -SqlServer $Instance -SqlCredential $Credential -Erroraction SilentlyContinue
			    }
		    catch
		        {
			    Write-Warning "Can't connect to $Instance"
			    continue
		        }
            Write-Verbose "Getting Server Level Triggers on $Instance"
            $server.Triggers | Select-Object @{l='ComputerName';e={$server.NetName}},@{l='SqlInstance';e={$server.ServiceName}}, @{l='Database';e={""}}, @{l='TriggerName';e={$_.Name}}, IsEnabled, DateLastModified
            Write-Verbose "Getting Database Level Triggers on $Instance"
            $server.Databases | Where-Object { $_.status -eq 'Normal'} |
            ForEach-Object {
                $db = $_.Name
                Write-Verbose "Getting Database Level Triggers on Database $db on $Instance"
                $_.Triggers | Select-Object @{l='ComputerName';e={$server.NetName}},@{l='SqlInstance';e={$server.ServiceName}}, @{l='Database';e={"$db"}}, @{l='TriggerName';e={$_.Name}}, IsEnabled, DateLastModified
                }
            }
    }
    END {}
}
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
		[Alias("SqlCredential")]
		[PsCredential]$Credential
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
            $server.Triggers | 
            ForEach-Object {
                    [PSCustomObject]@{
                            ComputerName     = $server.NetName
                            SqlInstance      = $server.ServiceName
                            TriggerLevel     = "Server"
                            Database         = $null
                            TriggerName      = $_.Name
                            Status           = switch ( $_.IsEnabled ) { $true {"Enabled"} $false {"Disabled"} }
                            DateLastModified = $_.DateLastModified
                            }
            }

            Write-Verbose "Getting Database Level Triggers on $Instance"
            $server.Databases | Where-Object { $_.status -eq 'Normal'} |
                ForEach-Object {
                    $DatabaseName = $_.Name
                    Write-Verbose "Getting Database Level Triggers on Database $DatabaseName on $Instance"
                    $_.Triggers | 
                        ForEach-Object {
                                [PSCustomObject]@{
                                    ComputerName     = $server.NetName
                                    SqlInstance      = $server.ServiceName
                                    TriggerLevel     = "Database"
                                    Database         = $DatabaseName
                                    TriggerName      = $_.Name
                                    Status           = switch ( $_.IsEnabled ) { $true {"Enabled"} $false {"Disabled"} }
                                    DateLastModified = $_.DateLastModified
                                    }
                        }
                }
        }
    }
    END {}
}

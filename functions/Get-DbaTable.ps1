function Get-DbaTable {
<#
<#
.SYNOPSIS
Returns a summary of encrption used on databases based to it.
.DESCRIPTION
Shows if a database has Transparaent Data encrption, any certificates, asymmetric keys or symmetric keys with details for each.
.PARAMETER SqlInstance
SQLServer name or SMO object representing the SQL Server to connect to. This can be a
collection and recieve pipeline input
.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, currend Windows login will be used.
.PARAMETER Database
Define the database you wish to search
.PARAMETER IncludeSystemDBs
Switch parameter that when used will display system database information
	
.PARAMETER Silent 
Use this switch to disable any kind of verbose messages
	
.NOTES 
Original Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	
.LINK
https://dbatools.io/Get-DbaDatabaseEncryption
.EXAMPLE
Get-DbaDatabaseEncryption -SqlInstance DEV01
List all encrpytion found on the instance by database
.EXAMPLE
Get-DbaDatabaseEncryption -SqlInstance DEV01 -Database MyDB
List all encrption found in MyDB 
#>
	[CmdletBinding()]
	param ([parameter(ValueFromPipeline, Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
        [string[]]$Table
	)

    DynamicParam { if ($SqlInstance) { return Get-ParamSqlDatabases -SqlInstance $SqlInstance[0] -SqlCredential $SourceSqlCredential } }

    BEGIN
	{
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
	}
 
    PROCESS
    {
			#For each SQL Server in collection, connect and get SMO object
			Write-Verbose "Connecting to $instance"
			
			try
			{
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			catch
			{
				Stop-Function -Message "Failed to connect to: $instance" -Continue -Target $instance
			}
			
			#If IncludeSystemDBs is true, include systemdbs
			#only look at online databases (Status equal normal)
			try
			{
				if ($databases.length -gt 0)
				{
					$dbs = $server.Databases | Where-Object { $databases -contains $_.Name }
				}
				elseif ($IncludeSystemDBs)
				{
					$dbs = $server.Databases | Where-Object { $_.status -eq 'Normal' }
				}
				else
				{
					$dbs = $server.Databases | Where-Object { $_.status -eq 'Normal' -and $_.IsSystemObject -eq 0 }
				}
				
				if ($exclude.length -gt 0)
				{
					$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
				}
			}
			catch
			{
				Stop-Function -Message "Unable to gather dbs for $instance" -Target $instance -Continue
			}
			
			foreach ($db in $dbs)
			{
				Write-Message -Level Verbose -Message "Processing $db"
			
                $d = $server.Databases[$db] 
                if ($Table)
                {
                    $db.Tables | Where {$_.name }
                }
                else
                {
                    $db.Tables | gm select name, schema, indexSpaceused, dataspaceused, rowCount, HasClusteredIndex, fu
                }
            }
        }
    }

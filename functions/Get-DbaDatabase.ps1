FUNCTION Get-DbaDatabase
{
<#
.SYNOPSIS
Gets SQL Database information for each database that is present in the target instance(s) of SQL Server.

.DESCRIPTION
 The Get-DbaDatabase command gets SQL database information for each database that is present in the target instance(s) of
 SQL Server. If the name of the database is provided, the command will return only the specific database information.
	
.PARAMETER SqlInstance
SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input to allow the function
to be executed against multiple SQL Server instances.

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, current Windows login will be used.

.PARAMETER IncludeSystemDb
Returns all SQL Server System databases from the SQL Server instance(s) executed against.

.PARAMETER IncludeUserDb
Returns SQL Server user databases from the SQL Server instance(s) executed against.
	
.PARAMETER State
Returns SQL Server databases in the status passed to the function.  Could include Emergency, Online, Offline, Recovering, Restoring, Standby or Suspect 
statuses of databases from the SQL Server instance(s) executed against.

.PARAMETER Access
Returns SQL Server databases that are Read Only or all other Online databases from the SQL Server intance(s) executed against.

.PARAMETER DatabaseOwner
Returns list of SQL Server databases not owned by SA from the SQL Server instance(s) executed against.

.PARAMETER Encrypted
Returns list of SQL Server databases that have TDE enabled from the SQL Server instance(s) executed against.

.PARAMETER RecoveryModel
Returns list of SQL Server databases in Full, Simple or Bulk Logged recovery models from the SQL Server instance(s) executed against.

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
https://dbatools.io/Get-DbaDatabase

.EXAMPLE
Get-DbaDatabase -SqlServer localhost
Returns all databases on the local default SQL Server instance

.EXAMPLE
Get-DbaDatabase -SqlServer localhost -IncludeSystemDb
Returns only the system databases on the local default SQL Server instance

.EXAMPLE
Get-DbaDatabase -SqlServer localhost -IncludeUserDb
Returns only the user databases on the local default SQL Server instance
	
.EXAMPLE
'localhost','sql2016' | Get-DbaDatabase
Returns databases on multiple instances piped into the function

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$IncludeSystemDb,
		[switch]$IncludeUserDb,
        [switch]$DatabaseOwner,
        [switch]$Encrypted,
		#[ValidateSet([enum]::GetValues([Microsoft.SqlServer.Management.Smo.DatabaseStatus]))]
        [ValidateSet('EmergencyMode', 'Normal', 'Offline', 'Recovering', 'Restoring', 'Standby', 'Suspect')]
        [string]$State,
		[ValidateSet('ReadOnly', 'ReadWrite')]
		[string]$Access,
        [ValidateSet('Full', 'Simple', 'BulkLogged')]
        [string]$RecoveryModel
	)
	
	DynamicParam { if ($SqlInstance) { return Get-ParamSqlDatabases -SqlServer $SqlInstance[0] -SqlCredential $SqlCredential } }
	
	BEGIN
	{
    	$databases = $psboundparameters.Databases
	}
	
	PROCESS
	{
		foreach ($instance in $SqlInstance)
		{
			try
			{
    			$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			catch
			{
				Write-Warning "Failed to connect to: $instance"
				continue
			}
			
			$defaults = 'Name', 'Status', 'ContainmentType', 'RecoveryModel', 'CompatibilityLevel', 'Collation', 'Owner', 'EncryptionEnabled'
			
			if ($IncludeSystemDb)
			{
            		$inputobject = $server.Databases | Where-Object { $_.IsSystemObject }
			}
			
			if ($IncludeUserDb)
			{
                $inputobject = $server.Databases | Where-Object { $_.IsSystemObject -eq $false }
			}
			
			if ($databases)
			{
                $inputobject = $server.Databases | Where-Object { $_.Name -in $databases }
			}
			
            switch ($state) 
            {
                "EmergencyMode" {$inputobject = $server.Databases | Where-Object { $_.status -eq 'EmergencyMode' }}
                "Normal" {$inputobject = $server.Databases | Where-Object { $_.status -eq 'Normal'}}
                "Offline" {$inputobject = $server.Databases | Where-Object { $_.status -eq 'Offline' }}
                "Recovering" {$inputobject = $server.Databases | Where-Object { $_.status -eq 'Recovering'}}
                "Restoring" {$inputobject = $server.Databases | Where-Object { $_.status -eq 'Restoring' }}
                "Standby" {$inputobject = $server.Databases | Where-Object { $_.status -eq 'Standby'}}
                "Suspect" {$inputobject = $server.Databases | Where-Object { $_.status -eq 'Suspect' }}
            }

            if ($DatabaseOwner)
            {    
                $inputobject = $server.Databases | Where-Object { $_.DatabaseOwner -ne 'sa'}
            }
			
            switch ($Access)
            {
                "ReadOnly" {$inputobject = $server.Databases | Where-Object { $_.ReadOnly }}
                "ReadWrite" {$inputobject = $server.Databases | Where-Object { $_.ReadOnly -eq $false }}
            }
            
            if ($Encrypted)
			{
            	$inputobject = $server.Databases | Where-Object { $_.EncryptionEnabled }
			}
			
            switch ($RecoveryModel)
            {
                "Full" {$inputobject = $server.Databases | Where-Object { $_.RecoveryModel -eq 'Full' }}
                "Simple" {$inputobject = $server.Databases | Where-Object { $_.RecoveryModel -eq 'Simple' }}
                "BulkLogged" {$inputobject = $server.Databases | Where-Object { $_.RecoveryModel -eq 'BulkLogged' }}
            }
         
           	Select-DefaultView -InputObject $inputobject  -Property $defaults
		}
	}
}

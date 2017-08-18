Function Test-DbaFullRecoveryModel
{
<#
.SYNOPSIS
Find if database is really in the Full recovery model or not.

.DESCRIPTION
When you switch a database into FULL recovery model, it will behave like a SIMPLE recovery model until a full backup is taken in order to begin a log backup chain.
This state is also known as 'pseudo-Simple'.

Inspired by Paul Randal's post (http://www.sqlskills.com/blogs/paul/new-script-is-that-database-really-in-the-full-recovery-mode/)
	
.PARAMETER SqlServer
The SQL Server instance.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Detailed
Returns default information plus 'Notes' column

.NOTES
Tags: DisasterRecovery, Backup
Original Author: Claudio Silva (@ClaudioESSilva)
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
https://dbatools.io/Test-DbaFullRecoveryModel

.EXAMPLE
Test-DbaFullRecoveryModel -SqlServer sql2005

Shows all databases which actual configured recovery model is FULL and says if they are really in FULL recovery model or not

.EXAMPLE
Test-DbaFullRecoveryModel -SqlServer . | Where-Object {$_.ActualRecoveryModel -ne "FULL"}

Only shows the databases that are in 'pseudo-simple' mode.
	
.EXAMPLE   
Test-DbaFullRecoveryModel -SqlServer sql2008 | Sort-Object Server, ActualRecoveryModel -Descending
	
Shows all databases which actual configured recovery model is FULL and says if they are really in FULL recovery model or not. Will show in first place the ones that are in 'pseudo-simple' mode.
	
#>
	[CmdletBinding()]
    [OutputType("System.Collections.ArrayList")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [switch]$Detailed
	)
    DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer -SqlCredential $SqlCredential } }
	
	BEGIN
	{
        # Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases

        $collection = New-Object System.Collections.ArrayList
	}
	
	PROCESS
	{
        foreach ($servername in $SqlServer)
		{
			try
			{
				$server = Connect-SqlServer -SqlServer $servername -SqlCredential $SqlCredential

                if ($server.versionMajor -lt 9)
		        {
			        Write-Warning "This function does not support versions lower than SQL Server 2005 (v9). Skipping server '$servername'."
                    continue
		        }

                $sqlRecoveryModel = "SELECT '$($server.Name)' AS 'Server'
                        , d.[name] AS [Database]
		                , d.recovery_model AS RecoveryModel
		                , d.recovery_model_desc AS RecoveryModelDesc
		                , CASE
			                WHEN d.recovery_model = 1 AND drs.last_log_backup_lsn IS NOT NULL THEN 1
			                ELSE 0
		                   END AS IsReallyInFullRecoveryModel
                  FROM sys.databases AS D
	                INNER JOIN sys.database_recovery_status AS drs
	                   ON D.database_id = drs.database_id
                  WHERE d.recovery_model = 1"

                if ($databases.length -gt 0)
		        {
			        $dblist = $databases -join "','"
			        $databasefilter += "AND d.[name] in ('$dblist')"
		        }

                $sql = "$sqlRecoveryModel $databasefilter"

                Write-Debug $sql

                $recoverymodel = $server.Databases['master'].ExecuteWithResults($sql)
                
                if ($recoverymodel.Tables[0].Rows.Count -eq 0)
                {
                    Write-Output "Server '$servername' does not have any databases in FULL recovery model."
                }
                else
                {
                    foreach ($recoverymodelrow in $recoverymodel.Tables[0])
                    {
                        if (!([bool]$recoverymodelrow.IsReallyInFullRecoveryModel))
                        {
                            $notes = "Database is still in SIMPLE recovery model until a full database backup is taken."
                            $ActualRecoveryModel = "pseudo-SIMPLE"
                        }
                        else
                        {
                            $notes = $null
                            $ActualRecoveryModel = "FULL"
                        }

                        $null = $collection.Add([PSCustomObject]@{
				    		    Server = $recoverymodelrow.Server
				    		    Database = $recoverymodelrow.Database
				    		    ConfiguredRecoveryModel = $recoverymodelrow.RecoveryModelDesc
                                ActualRecoveryModel = $ActualRecoveryModel
                                Notes = $notes
				    	    }) 
                    }
                }

                $server.ConnectionContext.Disconnect()
            }
            catch
            {
                throw $_
            }
        }
	}
	
	END
	{
        if ($Detailed)
        {
            return $collection
        }
        else
        {
            return ($collection | Select-Object * -ExcludeProperty notes)
        }
	}
}

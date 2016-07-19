Function Test-SqlMigrationConstraint
{
<#
.SYNOPSIS
Show if you can migrate the database(s) between the servers.

.DESCRIPTION
When you want to migrate from a higher edition to a lower one there are some features that can't be used.
This function will validate if you have any of this features in use and will report to you.
The validation will be made ONLY on on SQL Server 2008 or higher using the 'sys.dm_db_persisted_sku_features' dmv.

This function only validate SQL Server 2008 versions or higher.
The editions supported by this function are:
    - Enterprise
    - Developer
    - Evaluation
    - Standard
    - Express
	
The -Databases parameter is autopopulated for command-line completion.

.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, this pass this $dcred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	


.NOTES 
Original Author: Cláudio Silva (@ClaudioESSilva)
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
https://dbatools.io/Test-SqlMigrationConstraint

.EXAMPLE
Test-SqlMigrationConstraint -Source sqlserver2014a -Destination sqlcluster

Description

All databases will be verified for features in use that can't be supported on the destination server


.EXAMPLE   
Test-SqlMigrationConstraint -Source sqlserver2014a -Destination sqlcluster -SqlCredential $cred

Description

All databases will be verified for features in use that can't be supported on the destination server using SQL credentials for sqlserver2014a
and Windows credentials for sqlcluster.

.EXAMPLE   
Test-SqlMigrationConstraint -Source sqlserver2014a -Destination sqlcluster -Databases db1
Only db1 database will be verified for features in use that can't be supported on the destination server
	
#>
    [CmdletBinding(DefaultParameterSetName = "DbMigration", SupportsShouldProcess = $true)]
	Param (
            [parameter(Position = 1, Mandatory = $true, ValueFromPipeline = $True)]
		    [object]$Source,
		    [parameter(Position = 2, Mandatory = $true)]
		    [object]$Destination,
            [parameter(Position = 4)]
		    [System.Management.Automation.PSCredential]$SourceSqlCredential,
		    [parameter(Position = 5)]
		    [System.Management.Automation.PSCredential]$DestinationSqlCredential
    )
    DynamicParam { if ($source) { return Get-ParamSqlDatabases -SqlServer $source -SqlCredential $SourceSqlCredential } }

    BEGIN
	{
	    <#
			1804890536 = Enterprise
	        1872460670 = Enterprise Edition: Core-based Licensing
	        610778273 = Enterprise Evaluation
	        284895786 = Business Intelligence
	        -2117995310 = Developer
	        -1592396055 = Express
	        -133711905= Express with Advanced Services
	        -1534726760 = Standard
	        1293598313 = Web
	        1674378470 = SQL Database
		#>

        $editions = @{"Enterprise" = 10; "Developer" = 10; "Evaluation" = 10; "Standard" = 5; "Express" = 1}
    }
    PROCESS
    {

        # Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		
		if ($pipedatabase.Length -gt 0)
		{
			$Source = $pipedatabase[0].parent.name
			$databases = $pipedatabase.name
		}

		Write-Output "Attempting to connect to Sql Servers.."
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential

        if ($databases.Count -eq 0)
        {
            $databases = $sourceserver.Databases | Where-Object {$_.isSystemObject -eq 0} | Select-Object Name, Status
        }

        if ($databases.Count -gt 0)
        {
		    if ($databases -contains "master" -or $databases -contains "msdb" -or $databases -contains "tempdb") 
            { 
                throw "Migrating system databases is not currently supported." 
            }

            if ($sourceserver.versionMajor -lt 9 -and $destserver.versionMajor -gt 10)
		    {
			    throw "Sql Server 2000 databases cannot be migrated to Sql Server versions 2012 and above. Quitting."
		    }

            if ($sourceserver.collation -ne $destserver.collation)
		    {
			    Write-Warning "Collation on $Source, $($sourceserver.collation) differs from the $Destination, $($destserver.collation)."
		    }

            if ($sourceserver.versionMajor -gt $destserver.versionMajor)
		    {
                #indicate that must use 'Generate Scripts' and 'Export Data' options?
			    throw "You can't migrate databases from a higher version to a lower one. Quitting."
		    }

            if ($sourceserver.versionMajor -lt 10)
		    {
			    throw "This function does not support versions lower than SQL Server 2008 (v10)"
		    }

            #if editions differs, from higher to lower one, verify the sys.dm_db_persisted_sku_features
            #only available from SQL 2008 +
            if (($sourceserver.versionMajor -ge 10 -and $destserver.versionMajor -ge 10))
            {
                foreach ($db in $databases)
                {
                    if ([string]::IsNullOrEmpty($db.Status))          
                    {                        
                        $dbstatus = ($sourceserver.Databases | Where-Object {$_.Name -eq $db}).Status.ToString()
                        $dbName = $db
                    }
                    else
                    {
                        $dbstatus = $db.Status.ToString()
                        $dbName = $db.Name
                    }
                    Write-Host "`r`nChecking database: '$dbName'"

                    if ($dbstatus.Contains("Offline") -eq $false)
                    {
                        if ($editions.Item($destserver.Edition.ToString().Split(" ")[0]) -lt $editions.Item($sourceserver.Edition.ToString().Split(" ")[0]))
                        {
                            #validate if any features are being used
                            Write-Verbose "Source Server Edition: $($sourceserver.Edition) (Weight: $($editions.Item($sourceserver.Edition.ToString().Split(" ")[0])))"
                            Write-Verbose "Destination Server Edition: $($destserver.Edition) (Weight: $($editions.Item($destserver.Edition.ToString().Split(" ")[0])))"

			                try 
                            {
                                $sql = "SELECT feature_name FROM sys.dm_db_persisted_sku_features"

                                $skufeatures = $sourceserver.Databases[$dbName].ExecuteWithResults($sql)

                                Write-Verbose "Checking features in use..."
                                if ($skufeatures.Tables[0].Rows.Count -gt 0)
                                {
                                    $feature = ""

                                    foreach ($row in $skufeatures.Tables[0].Rows)
                                    {
                                        $feature += "$($row["feature_name"])`r`n"
                                    }
                            
                                    $message = "'$dbName' cannot be migrated to '$($destserver.Name)' ($($destserver.Edition). The following features are unsupported:`r`n$($feature)"
                                    Write-Warning $message

                                    $dbFail = $true
                                }
                                else
                                {
                                    Write-Output "You can migrate database '$dbName'! Does not exist any feature in use that you can't use on the destination version."
                                }
                            }
			                catch
                            { 
                                throw "Can't execute SQL on $sourceserver. `r`n $($_)"
                            }
                        }
                        else
                        {
                            Write-Output "You can migrate database '$dbName'! The destination version and edition are equal or higher."
                        }
                    }
                    else
                    {
                        Write-Warning "Database '$dbName' is offline. Bring database online and re-run the command"
                    }
                
                }
                if ($dbFail)
                {
                    Write-Host "`r`n"
                    Write-Warning "One or more databases will fail. For more information please see: https://msdn.microsoft.com/en-us/library/cc280724(v=sql.130).aspx"
                }
            }
            else
            {
                #SQL Server 2005 or under
                Write-Warning "This validation will not be made on versions lower than SQL Server 2008 (v10)"
                Write-Verbose "Source server version: $($sourceserver.versionMajor)"
                Write-Verbose "Destination server version: $($destserver.versionMajor)"
            }
        }
        else
        {
            Write-Output "There are no databases to migrate."
        }
    }
    END
    {
        $sourceserver.ConnectionContext.Disconnect()
        $destserver.ConnectionContext.Disconnect()
    }
}
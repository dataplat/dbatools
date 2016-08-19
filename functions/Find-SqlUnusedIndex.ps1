Function Find-SqlUnusedIndex
{
<#
.SYNOPSIS
Find Unused indexes

.DESCRIPTION
This command will help you to find Unused indexes on a database or a list of databases

Also tells how much space you can save by dropping the index.
We show the type of compression so you can make a more considered decision.
For now only supported for CLUSTERED and NONCLUSTERED indexes

You can select the indexes you want to drop on the gridview and by click OK the drop statement will be generated.

Output:
    TableName
    IndexName
    KeyCols
    IncludedCols
    IndexSizeMB
    IndexType
    CompressionDesc (When 2008+)
    NumberRows
    IsDisabled
    IsFiltered (When 2008+)
	
.PARAMETER SqlServer
The SQL Server instance.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER FileName
The file to write to.

.PARAMETER NoClobber
Do not overwrite file
	
.PARAMETER Append
Append to file

.NOTES 
Original Author: Aaron Nelson (@SQLvariant), SQLvariant.com
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
https://dbatools.io/Find-SqlUnusedIndex

.EXAMPLE
Find-SqlUnusedIndex -SqlServer sql2005 -FilePath C:\temp\sql2005-UnusedIndexes.sql

Exports SQL for the Unused indexes in server "sql2005" choosen on grid-view and writes them to the file "C:\temp\sql2005-UnusedIndexes.sql"
	
.EXAMPLE
Find-SqlUnusedIndex -SqlServer sql2005 -FilePath C:\temp\sql2005-UnusedIndexes.sql -Append

Exports SQL for the Unused indexes in server "sql2005" choosen on grid-view and writes/appends them to the file "C:\temp\sql2005-UnusedIndexes.sql"

.EXAMPLE   
Find-SqlUnusedIndex -SqlServer sqlserver2016 -SqlCredential $cred
	
Will find exact Unused indexes on all user databases present on sqlserver2016 will be verified using SQL credentials. 
	
.EXAMPLE   
Find-SqlUnusedIndex -SqlServer sqlserver2016 -Databases db1, db2

Will find exact Unused indexes on both db1 and db2 databases

.EXAMPLE   
Find-SqlUnusedIndex -SqlServer sqlserver2016

Will find exact Unused indexes on all user databases 
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
        [object]$SqlCredential,
        [Alias("OutFile", "Path")]
		[string]$FilePath,
        [switch]$NoClobber,
		[switch]$Append
	)
    DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer -SqlCredential $SqlCredential } }
	
	BEGIN
	{
        
        # Support Compression 2008+
		$CompletelyUnusedQuery = "SELECT  DB_NAME(database_id) AS 'DatabaseName',
        s.name AS 'SchemaName', 
		t.name AS 'TableName',  
		i.object_id ,
        i.name AS 'IndexName',
        i.index_id,
        i.type_desc ,
        user_seeks ,
        user_scans ,
        user_lookups ,
        user_updates ,
        last_user_seek ,
        last_user_scan ,
        last_user_lookup ,
        last_user_update ,
        system_seeks ,
        system_scans ,
        system_lookups ,
        system_updates ,
        last_system_seek ,
        last_system_scan ,
        last_system_lookup ,
        last_system_update
  FROM SYS.TABLES T
  JOIN SYS.SCHEMAS S
    ON T.schema_id = s.schema_id
  JOIN SYS.indexes i
    ON i.object_id = t.object_id
  LEFT OUTER JOIN sys.dm_db_index_usage_stats iu
    ON iu.object_id = i.object_id
   AND iu.index_id = i.index_id
 WHERE iu.database_id = DB_ID()
   AND OBJECTPROPERTY(i.[object_id], 'IsMSShipped') = 0
   AND user_seeks	= 0	
   AND user_scans	= 0	
   AND user_lookups	= 0
   AND i.type_desc NOT IN ('HEAP', 'CLUSTERED COLUMNSTORE')"

        if ($FilePath.Length -gt 0)
		{
			$directory = Split-Path $FilePath
			$exists = Test-Path $directory
			
			if ($exists -eq $false)
			{
				throw "Parent directory $directory does not exist"
			}
		}

        Write-Output "Attempting to connect to Sql Server.."
		$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	}
	
	PROCESS
	{

        if ($server.versionMajor -lt 9)
		{
			throw "This function does not support versions lower than SQL Server 2005 (v9)"
		}
		
		$lastrestart = $server.Databases['tempdb'].CreateDate
		$enddate = Get-Date -Date $lastrestart
		$diffdays = (New-TimeSpan -Start $enddate -End (Get-Date)).Days
		
		if ($diffdays -le 6)
		{
			throw "The SQL Service was restarted on $lastrestart, which is not long enough for a solid evaluation."
		}
        
        <#
            Validate if server version is:
                - sql 2012 and if have SP3 CU3 (Build 6537) or higher
                - sql 2014 and if have SP2 (Build 5000) or higher
            If the major version is the same but the build is lower, throws the message
        #>
        if (
                ($server.VersionMajor -eq 11 -and $server.BuildNumber -lt 6537) `
            -or ($server.VersionMajor -eq 12 -and $server.BuildNumber -lt 5000)
           )
        {
            throw "This SQL version has a known issue. Rebuilding an index clears any existing row entry from sys.dm_db_index_usage_stats for that index.`r`nPlease refer to connect item: https://connect.microsoft.com/SQLServer/feedback/details/739566/rebuilding-an-index-clears-stats-from-sys-dm-db-index-usage-stats"
        }
		
		if ($diffdays -le 33)
		{
			Write-Warning "The SQL Service was restarted on $lastrestart, which may not be long enough for a solid evaluation."
		}
		
		# Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		
		if ($pipedatabase.Length -gt 0)
		{
			$Source = $pipedatabase[0].parent.name
			$databases = $pipedatabase.name
		}

        if ($databases.Count -eq 0)
        {
            $databases = ($server.Databases | Where-Object {$_.isSystemObject -eq 0 -and $_.Status -ne "Offline"}).Name
        }

        if ($databases.Count -gt 0)
        {
            foreach ($db in $databases)
            {
                try
                {
                    Write-Output "Getting indexes from database '$db'"

                    $query = $CompletelyUnusedQuery

                    $UnusedIndex = $server.Databases[$db].ExecuteWithResults($query)

                    $scriptGenerated = $false

                    if ($UnusedIndex.Tables[0].Rows.Count -gt 0)
                    {
                        $indexesToDrop = $UnusedIndex.Tables[0] | Out-GridView -Title "Unused Indexes on $($db) database - Choose indexes to generate DROP script" -PassThru

                        #When only 1 line selected, the count does not work
                        if ($indexesToDrop.Count -gt 0 -or !([string]::IsNullOrEmpty($indexesToDrop)))
                        {
                            #reset to #Yes
                            $result = 0

                            if ($UnusedIndex.Tables[0].Rows.Count -eq $indexesToDrop.Count)
                            {
                                $title = "Indexes to drop on databases '$db':"
                                $message = "You will generate drop statements to all indexes.`r`nPerhaps you want to keep at least one.`r`nDo you wish to generate the script anyway? (Y/N)"
                                $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
                                $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
                                $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                                $result = $host.ui.PromptForChoice($title, $message, $options, 0)
                            }

                            if ($result -eq 0) #default OR answer = YES
                            {
                                $sqlDropScript = "/*`r`n"
                                $sqlDropScript += "`tScript generated @ $(Get-Date -format "yyyy-MM-dd HH:mm:ss.ms")`r`n"
                                $sqlDropScript += "`tDatabase: $($db)`r`n"
                                $sqlDropScript += "`tConfirm that you have choosen the right indexes before execute the drop script`r`n"
                                $sqlDropScript += "*/`r`n"

                                foreach ($index in $indexesToDrop)
                                {
                                    if ($FilePath.Length -gt 0)
				                    {
					                    Write-Output "Exporting $($index.TableName).$($index.IndexName)"
				                    }

                                    $sqlDropScript += "USE [$($index.DatabaseName)]`r`n"
                                    $sqlDropScript += "GO`r`n"
                                    $sqlDropScript += "IF EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('$($index.TableName)') AND name = '$($index.IndexName)')`r`n"
                                    $sqlDropScript += "    DROP INDEX $($index.TableName).$($index.IndexName)`r`n"
                                    $sqlDropScript += "GO`r`n`r`n"
                                }

                                if ($FilePath.Length -gt 0)
		                        {
			                        $sqlDropScript | Out-File -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
		                        }
                                else
                                {
                                    Write-Output $sqlDropScript
                                }

                                $scriptGenerated = $true
                            }
                            else #answer = no
                            {
                                Write-Warning "Script will not be generated for database '$db'"
                            }
                        }
                    }
                    else
                    {
                        Write-Output "No Unused indexes found!"
                    }
                }
                catch
                {
                    throw $_
                }
            }

            if ($scriptGenerated)
            {
                Write-Warning "Confirm the generated script before execute!"
            }
            if ($FilePath.Length -gt 0)
            {
                Write-Output "Script generated to $FilePath"
            }
        }
        else
        {
            Write-Output "There are no databases to analyse."
        }
	}
	
	END
	{
		$server.ConnectionContext.Disconnect()
	}
}
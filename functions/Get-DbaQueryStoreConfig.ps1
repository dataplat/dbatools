Function Get-DbaQueryStoreConfig
{
<#
.SYNOPSIS
Get the Query Store configuration for all Query Store enabled databases.
	
.DESCRIPTION
Retrieves and returns the Query Store configuration for every database that has the Query Store feature enabled.

Default output includes
	
.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user.

.PARAMETER Databases
Return information for only specific databases

.PARAMETER Exclude
Return information for all but these specific databases

.NOTES
Author: Enrico van de Laar ( @evdlaar )

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.


.LINK
https://dbatools.io/Get-QueryStoreConfig

.EXAMPLE
Get-DbaQueryStoreConfig -SqlServer ServerA\sql

Returns Query Store configuration settings for every Query Store enabled database on the ServerA\sql instance.

	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[PsCredential]$Credential
	)

	DynamicParam {
		if ($SqlServer) {
			return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $Credential
		}
	}

	BEGIN
	{
		# Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude

        # Create a datatable to hold the Query Store configuration
        $QSCDT = New-Object System.Data.DataTable

        # Define the columns
        $QSCDT_Instance = New-Object System.Data.DataColumn ‘Instance’,([string])
        $QSCDT_Database = New-Object System.Data.DataColumn ‘Database’,([string])
        $QSCDT_ActualState = New-Object System.Data.DataColumn ‘ActualState’,([string])
        $QSCDT_FlushInterval = New-Object System.Data.DataColumn ‘FlushInterval’,([string])
        $QSCDT_CollectionInterval = New-Object System.Data.DataColumn ‘CollectionInterval’,([string])
        $QSCDT_MaxSize = New-Object System.Data.DataColumn ‘MaxSize’,([string])
        $QSCDT_CurrentSize = New-Object System.Data.DataColumn ‘CurrentSize’,([string])
        $QSCDT_CaptureMode = New-Object System.Data.DataColumn ‘CaptureMode’,([string])
        $QSCDT_CleanupMode = New-Object System.Data.DataColumn ‘CleanupMode’,([string])
        $QSCDT_StaleQueryThreshold = New-Object System.Data.DataColumn ‘StaleQueryThreshold’,([string])

        # Add columns to the datatable
        $QSCDT.Columns.Add($QSCDT_Instance)
        $QSCDT.Columns.Add($QSCDT_Database)
        $QSCDT.Columns.Add($QSCDT_ActualState)
        $QSCDT.Columns.Add($QSCDT_FlushInterval)
        $QSCDT.Columns.Add($QSCDT_CollectionInterval)
        $QSCDT.Columns.Add($QSCDT_MaxSize)
        $QSCDT.Columns.Add($QSCDT_CurrentSize)
        $QSCDT.Columns.Add($QSCDT_CaptureMode)
        $QSCDT.Columns.Add($QSCDT_CleanupMode)
        $QSCDT.Columns.Add($QSCDT_StaleQueryThreshold)
	}

	PROCESS
	{
		foreach ($servername in $SqlServer)
		{
            Write-Verbose "Connecting to $servername"
			try
			{
				$server = Connect-SqlServer -SqlServer $servername -SqlCredential $Credential

			}
			catch
			{
				if ($SqlServer.count -eq 1)
				{
					throw $_
				}
				else
				{
					Write-Warning "Can't connect to $servername. Moving on."
					Continue
				}
			}

            $sqlVersion = $server.Version

            $sqlVersion = $sqlVersion.ToString().Split(".")[0]

            if($sqlVersion -ilt "13")
                {

                Write-Warning "The SQL Server Instance has a lower SQL Server version than SQL Server 2016. Skipping server."
                break
                }

            
            # We have to exclude all the system databases since they cannot have the Query Store feature enabled
			$dbs = $server.Databases | Where-Object { $_.name -ne 'TempDb' -and $_.name -ne 'master' -and $_.name -ne 'msdb' -and $_.name -ne 'model' }

			if ($databases.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $databases -contains $_.Name }
			}

			if ($exclude.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
			}


			foreach ($db in $dbs)
			{
                $result = $null
				Write-Verbose "Processing $($db.name) on $servername"

				if ($db.IsAccessible -eq $false)
				{
					Write-Warning "The database $($db.name) on server $servername is not accessible. Skipping database."
					Continue
				}

                # Start processing

                $QSCDT_Row = $QSCDT.NewRow()

                $QSCDT_Row.Instance = $servername
                $QSCDT_Row.Database = $db.name
                $QSCDT_Row.ActualState = $db.QueryStoreOptions.ActualState
                $QSCDT_Row.FlushInterval = $db.QueryStoreOptions.DataFlushIntervalInSeconds
                $QSCDT_Row.CollectionInterval = $db.QueryStoreOptions.StatisticsCollectionIntervalInMinutes
                $QSCDT_Row.MaxSize = $db.QueryStoreOptions.MaxStorageSizeInMB
                $QSCDT_Row.CurrentSize = $db.QueryStoreOptions.CurrentStorageSizeInMB
                $QSCDT_Row.CaptureMode = $db.QueryStoreOptions.QueryCaptureMode
                $QSCDT_Row.CleanupMode = $db.QueryStoreOptions.SizeBasedCleanupMode
                $QSCDT_Row.StaleQueryThreshold = $db.QueryStoreOptions.StaleQueryThresholdInDays

                $QSCDT.Rows.Add($QSCDT_Row)
                       
			}
        }

    $QSCDT | Format-Table -Property Instance, Database, ActualState, FlushInterval, CollectionInterval, MaxSize, CurrentSize, CaptureMode, CleanupMode, StaleQueryThreshold -Wrap -AutoSize 

    }
	
}
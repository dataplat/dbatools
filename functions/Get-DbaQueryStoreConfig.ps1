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

Returns Query Store configuration settings for every database on the ServerA\sql instance.

.EXAMPLE
Get-DbaQueryStoreConfig -SqlServer ServerA\sql | Where-Object {$_.ActualState -eq "ReadWrite"}

Returns the Query Store configuration for all databases on ServerA\sql where the Query Store feature is in Read/Write mode.

.EXAMPLE
Get-DbaQueryStoreConfig -SqlServer localhost | format-table -AutoSize -Wrap

Returns Query Store configuration settings for every database on the ServerA\sql instance inside a table format.

	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[PsCredential]$Credential,
        [string[]]$State
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

            $sqlVersion = $server.VersionMajor

            if($sqlVersion -ilt "13")
                {

                Write-Warning "The SQL Server Instance ($servername) has a lower SQL Server version than SQL Server 2016. Skipping server."
                continue
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

                [pscustomobject]@{
                Instance = $servername
                Database = $db.name
                ActualState = $db.QueryStoreOptions.ActualState
                FlushInterval = $db.QueryStoreOptions.DataFlushIntervalInSeconds
                CollectionInterval = $db.QueryStoreOptions.StatisticsCollectionIntervalInMinutes
                MaxSize = $db.QueryStoreOptions.MaxStorageSizeInMB
                CurrentSize = $db.QueryStoreOptions.CurrentStorageSizeInMB
                CaptureMode = $db.QueryStoreOptions.QueryCaptureMode
                CleanupMode = $db.QueryStoreOptions.SizeBasedCleanupMode
                StaleQueryThreshold = $db.QueryStoreOptions.StaleQueryThresholdInDays
                }
                      
			}
        }

    }
	
}
Function Set-DbaQueryStoreConfig
{
<#
.SYNOPSIS
Configure Query Store settings for a specific or multiple databases.
	
.DESCRIPTION
Configure Query Store settings for a specific or multiple databases.
	
.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user.

.PARAMETER Databases
Set Query Store configuration for specific databases.

.PARAMETER Exclude
Set Query Store configuration for all databases on the connected server except databases entered through this parameter.

.PARAMETER State
Set the state of the Query Store. Valid options are "ReadWrite", "ReadOnly" and "Off".

.PARAMETER FlushInterval
Set the flush to disk interval of the Query Store in seconds.

.PARAMETER CollectionInterval
Set the runtime statistics collection interval of the Query Store in minutes.

.PARAMETER MaxSize
Set the maximum size of the Query Store in MB.

.PARAMETER CaptureMode
Set the query capture mode of the Query Store. Valid options are "Auto" and "All".

.PARAMETER CleanupMode
Set the query cleanup mode policy. Valid options are "Auto" and "Off".

.PARAMETER StaleQueryThreshold
Set the stale query threshold in days.

.NOTES
Author: Enrico van de Laar ( @evdlaar )

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
https://dbatools.io/Set-QueryStoreConfig

.EXAMPLE
Set-DbaQueryStoreConfig -SqlServer ServerA\SQL -State ReadWrite -FlushInterval 600 -CollectionInterval 10 -MaxSize 100 -CaptureMode All -CleanupMode Auto -StaleQueryThreshold 100

Configure the Query Store settings for all user databases in the ServerA\SQL Instance.

.EXAMPLE
Set-DbaQueryStoreConfig -SQLServer ServerA\SQL -FlushInterval 600

Only configure the FlushInterval setting for all Query Store databases in the ServerA\SQL Instance.

.EXAMPLE
Set-DbaQueryStoreConfig -SqlServer ServerA\SQL -Databases AdventureWorks -State ReadWrite -FlushInterval 600 -CollectionInterval 10 -MaxSize 100 -CaptureMode all -CleanupMode Auto -StaleQueryThreshold 100

Configure the Query Store settings for the AdventureWorks database in the ServerA\SQL Instance.

.EXAMPLE
Set-DbaQueryStoreConfig -SqlServer ServerA\SQL -Exclude AdventureWorks -State ReadWrite -FlushInterval 600 -CollectionInterval 10 -MaxSize 100 -CaptureMode all -CleanupMode Auto -StaleQueryThreshold 100

Configure the Query Store settings for all user databases except the AdventureWorks database in the ServerA\SQL Instance.
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[PsCredential]$Credential,
        [ValidateSet(“ReadWrite”,”ReadOnly”,”Off”)][string[]]$State,
        [int64]$FlushInterval,
        [int64]$CollectionInterval,
        [int64]$MaxSize,
        [ValidateSet(“Auto”,”All”)][string[]]$CaptureMode,
        [ValidateSet(“Auto”,”Off”)][string[]]$CleanupMode,
        [int64]$StaleQueryThreshold
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

                if ($State)
                {
                $db.QueryStoreOptions.DesiredState = $State
                }

                if ($FlushInterval)
                {                
                $db.QueryStoreOptions.DataFlushIntervalInSeconds = $FlushInterval
                }

                if ($CollectionInterval)
                {
                $db.QueryStoreOptions.StatisticsCollectionIntervalInMinutes = $CollectionInterval
                }

                if ($MaxSize)
                {
                $db.QueryStoreOptions.MaxStorageSizeInMB = $MaxSize
                }

                if ($CaptureMode)
                {
                $db.QueryStoreOptions.QueryCaptureMode = $CaptureMode
                }

                if ($CleanupMode)
                {
                $db.QueryStoreOptions.SizeBasedCleanupMode = $CleanupMode
                }

                if ($StaleQueryThreshold)
                {
                $db.QueryStoreOptions.StaleQueryThresholdInDays = $StaleQueryThreshold
                }

                # Alter the Query Store Configuration
                Write-Verbose "Altering Query Store configuration on database $($db.name)."

                $db.QueryStoreOptions.Alter()
                      
			}
        }

    }
	
}
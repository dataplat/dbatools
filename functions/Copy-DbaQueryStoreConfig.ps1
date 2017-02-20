Function Copy-DbaQueryStoreConfig
{
<#
.SYNOPSIS
Copies the configuration of a Query Store enabled database and sets the copied configuration on other databases.
	
.DESCRIPTION
Copies the configuration of a Query Store enabled database and sets the copied configuration on other databases.
	
.PARAMETER SourceSqlServer
The SQL Server that you're connecting to.

.PARAMETER SourceDatabase
The database from which you want to copy the Query Store configuration.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user.

.PARAMETER TargetSqlServer
The target server where the databases reside on which you want to enfore the copied Query Store configuration from the SourceDatabase.

.PARAMETER Databases
The databases that will recieve a copy of the Query Store configuration of the SourceDatabase.

.PARAMETER Exclude
Copy Query Store configuration for all but these specific databases.

.NOTES
Author: Enrico van de Laar ( @evdlaar )

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
https://dbatools.io/Copy-QueryStoreConfig

.EXAMPLE
Copy-DbaQueryStoreConfig -SourceSqlServer ServerA\SQL -SourceDatabase AdventureWorks -TargetSqlServer ServerB\SQL

Copy the Query Store configuration of the AdventureWorks database in the ServerA\SQL Instance and apply it on all user databases in the ServerB\SQL Instance.

.EXAMPLE
Copy-DbaQueryStoreConfig -SourceSqlServer ServerA\SQL -SourceDatabase AdventureWorks -TargetSqlServer ServerB\SQL -Databases WorldWideTraders

Copy the Query Store configuration of the AdventureWorks database in the ServerA\SQL Instance and apply it to the WorldWideTraders database in the ServerB\SQL Instance.
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)][string[]]$SourceSqlServer,
        [parameter(Mandatory = $true, ValueFromPipeline = $true)][string[]]$SourceDatabase,
        [parameter(Mandatory = $true, ValueFromPipeline = $true)][string[]]$TargetSqlServer,
		[PsCredential]$Credential
	)

	DynamicParam {
		if ($SourceSqlServer) {
			return Get-ParamSqlDatabases -SqlServer $TargetSqlServer[0] -SqlCredential $Credential
		}
	}

	BEGIN
	{
		# Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude

        Write-Verbose "Connecting to source: $SourceSqlServer"
			try
			{
				$server = Connect-SqlServer -SqlServer $SourceSqlServer -SqlCredential $Credential

			}
			catch
			{
				if ($SourceSqlServer.count -eq 1)
				{
					throw $_
				}
				else
				{
					Write-Warning "Can't connect to $SourceSqlServer."
					Continue
				}
			}

        # Grab the Query Store configuration from the SourceDatabase through the Get-DbaQueryStoreConfig function
        $SourceQSConfig = Get-DbaQueryStoreConfig -SqlServer $SourceSqlServer -Databases $SourceDatabase

	}

	PROCESS
	{

        Write-Verbose "Connecting to target: $TargetSqlServer"
        try
		{
			$targetserver = Connect-SqlServer -SqlServer $TargetSqlServer -SqlCredential $Credential

		}
		catch
		{
			if ($TargetSqlServer.count -eq 1)
			{
				throw $_
			}
			else
			{
				Write-Warning "Can't connect to $TargetSqlServer."
				Continue
			}
		}

        $sqlVersion = $targetserver.VersionMajor

        if($sqlVersion -ilt "13")
        {
        Write-Warning "The SQL Server Instance ($TargetSqlServer) has a lower SQL Server version than SQL Server 2016. Skipping server."
        continue
        }

        # We have to exclude all the system databases since they cannot have the Query Store feature enabled
		$dbs = $targetserver.Databases | Where-Object { $_.name -ne 'TempDb' -and $_.name -ne 'master' -and $_.name -ne 'msdb' -and $_.name -ne 'model' }

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
			Write-Verbose "Processing target database: $($db.name) on $targetservername"

			if ($db.IsAccessible -eq $false)
			{
				Write-Warning "The database $($db.name) on server $targetservername is not accessible. Skipping database."
				Continue
			}
            
            # Set the Query Store configuration through the Set-DbaQueryStoreConfig function
            Set-DbaQueryStoreConfig -SqlServer $TargetSqlServer -Databases $($db.name) -State $SourceQSConfig.ActualState -FlushInterval $SourceQSConfig.FlushInterval -CollectionInterval $SourceQSConfig.CollectionInterval -MaxSize $SourceQSConfig.MaxSize -CaptureMode $SourceQSConfig.CaptureMode -CleanupMode $SourceQSConfig.CleanupMode -StaleQueryThreshold $SourceQSConfig.StaleQueryThreshold
                      
		}  


    }
	
}
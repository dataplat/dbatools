Function Invoke-DbaDatabaseUpgrade {
<#
	.SYNOPSIS
		Take a database and upgrades it to compatability of the SQL Instance its hosted on. Based on https://thomaslarock.com/2014/06/upgrading-to-sql-server-2014-a-dozen-things-to-check/
	
	.DESCRIPTION
		Updates compatability level, then runs CHECKDB with data_purity, DBCC updateusage, sp_updatestats and finally sp_refreshview against all user views. 
	
	.PARAMETER SqlInstance
		A description of the SqlInstance parameter.
	
	.PARAMETER SqlCredential
		A description of the SqlCredential parameter.
	
	.PARAMETER Database
		A description of the Database parameter.
	
	.PARAMETER IgnoreCompatabilityUpgrade
		A description of the IgnoreCompatabilityUpgrade parameter.
	
	.PARAMETER IgnoreCheckDB
		A description of the IgnoreCheckDB parameter.
	
	.PARAMETER IgnoreUpdateUsage
		A description of the IgnoreUpdateUsage parameter.
	
	.PARAMETER IgnoreUpdatstats
		A description of the IgnoreUpdatstats parameter.
	
	.PARAMETER IgnoreUpdateView
		A description of the IgnoreUpdateView parameter.

    .NOTES
        dbatools PowerShell module (https://dbatools.io)
        Copyright (C) 2016 Chrissy LeMaire
        This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
        This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
        You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

    .LINK
        https://dbatools.io/Invoke-DbaDatabaseUpgrade
	
	.EXAMPLE
		Update-Database -SqlInstance PRD-SQL-MSD01 -Database Test
		
		Runs the below processes against the databases
		-- Puts compatability of database to level of SQL Instance
		-- Runs CHECKDB DATA_PRUITY
		-- Runs DBCC UPDATESUSAGE
		-- Updates all users staistics
		-- Runs sp_refreshview against every view in the database
	
	.EXAMPLE
		Invoke-DbaDatabaseUpgrade -SqlInstance PRD-SQL-INT01 -Database Test -IgnoreCompatabilityUpgrade -IgnoreUpdateView
		
		Runs the upgrade command skipping the compatability update and running sp_refreshview on all views in the database
#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[Parameter(Mandatory = $true)]
		[string]$Database,
		[switch]$IgnoreCompatabilityUpgrade,
		[switch]$IgnoreCheckDB,
		[switch]$IgnoreUpdateUsage,
		[switch]$IgnoreUpdatstats,
		[switch]$IgnoreUpdateView,
		[switch]$Silent
	)
	begin {
		
	}
	process {
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level VeryVerbose -Message "Connecting to <c='green'>$instance</c>" -Target $instance
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
			}
			
			if (-not ($server.Databases.Name -eq $Database)) {
				Stop-Function -Message "No database with name exists on the server" -Target $instance -Continue -Category ObjectNotFound
			}
			
			# create objects to use in updates
			$ServerVersion = $server.VersionMajor
			Write-Message -Level Verbose -Message "SQL Server is using Version: $ServerVersion" -Target $instance
			$db = $server.Databases[$Database]
			
			if (-not $IgnoreCompatabilityUpgrade) {
				Write-Message -Level Verbose -Message "Updating $Database compatability to SQL Instance level"
				switch ($db.CompatibilityLevel) {
					"Version100"  { $dbversion = 10 } # SQL Server 2008
					"Version110"  { $dbversion = 11 } # SQL SERver 2012
					"Version120"  { $dbversion = 12 } # SQL Server 2014
					"Version130"  { $dbversion = 13 } # SQL Server 2016
					default { $dbversion = 9 }
				}
				
				if ($dbverison -lt $ServerVersion) {
					Write-Message -Level Output -Message "Updating database version from $dbversion to $ServerVersion"
					$Comp = $ServerVersion * 10
					$tsqlComp = "ALTER DATABASE [$Database] SET COMPATIBILITY_LEVEL = $Comp"
					try {
						$server.Databases["master"].ExecuteNonQuery($tsqlComp)
						$comResult = $Comp
					}
					catch {
						Write-Message -Level Warning -Message "Failed run Compatability Upgrade" -ErrorRecord $_ -Target $instance
						$comResult = "Fail"
					}
				}
			}
			else {
				Write-Message -Level Verbose -Message "Ignoring Compatability settings"
				$comResult = "Skipped"
			}
			
			if (!($IgnoreCheckDB)) {
				Write-Message -Level Verbose -Message "Updating $database with DBCC CHECKDB DATA_PURITY"
				$tsqlCheckDB = "DBCC CHECKDB ('$Database') WITH DATA_PURITY, NO_INFOMSGS"
				try {
					$server.Databases["master"].ExecuteNonQuery($tsqlCheckDB)
					$DataPurityResult = "Success"
				}
				catch {
					Write-Message -Level Warning -Message "Failed run DBCC CHECKDB with DATA_PURITY" -ErrorRecord $_ -Target $instance
					$DataPurityResult = "Fail"
				}
			}
			else {
				Write-Message -Level Verbose -Message "Ignoring CHECKDB DATA_PRUITY"
			}
			
			if (!($IgnoreUpdateUsage)) {
				Write-Message -Level Verbose -Message "Updating $database with DBCC UPDATEUSAGE"
				$tsqlUpdateUsage = "DBCC UPDATEUSAGE ($Database) WITH NO_INFOMSGS;"
				try {
					$server.Databases["master"].ExecuteNonQuery($tsqlUpdateUsage)
					$UpdateUsageResult = "Success"
				}
				catch {
					Write-Message -Level Warning -Message "Failed to run DBCC UPDATEUSAGE" -ErrorRecord $_ -Target $instance
					$UpdateUsageResult = "Fail"
				}
			}
			else {
				Write-Message -Level Verbose -Message "Ignore DBCC UPDATEUSAGE"
				 $UpdateUsageResult = "Skipped"
			}
			
			if (!($IgnoreUpdatstats)) {
				Write-Message -Level Verbose -Message "Updating $database statistics"
				$tsqlStats = "EXEC sp_updatestats;"
				try {
					$server.Databases[$Database].ExecuteNonQuery($tsqlStats)
					$UpdateStatsResult = "Success"
				}
				catch {
					Write-Message -Level Warning -Message "Failed to run sp_updatestats" -ErrorRecord $_ -Target $instance
					$UpdateStatsResult = "Fail"
				}
			}
			else {
				Write-Message -Level Verbose -Message "Ignoring sp_updatestats"
				$UpdateStatsResult = "Skipped"
			}
			
			if (!($IgnoreUpdateView)) {
				Write-Message -Level Verbose -Message "Updating all $database views"
				$dbViews = $db.Views | Where-Object IsSystemObject -eq $false
				$UpdateViewResult = "Success"
				foreach ($dbview in $dbviews) {
					$viewName = $dbView.Name
					$viewSchema = $dbView.Schema
					$fullName = $viewSchema + "." + $viewName
					
					$tsqlupdateView = "EXECUTE sp_refreshview N'$fullName';  "
					
					try {
						$server.Databases[$Database].ExecuteNonQuery($tsqlupdateView)
					}
					catch {
						Write-Message -Level Warning -Message "Failed update view $fullName" -ErrorRecord $_ -Target $instance
						$UpdateViewResult = "Fail"
					}
				}
			}
			else {
				Write-Message -Level Verbose -Message "Ignore View Updates"
				$UpdateViewResult = "Skipped"
			}

			[PSCustomObject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance = $server.DomainInstanceName
                        Database = $Database
                        Compatability = $comResult
                        DataPurity = $DataPurityResult
						UpdateUsage = $UpdateUsageResult
						UpdateStats = $UpdateStatsResult
						UpdateViews = $UpdateViewResult
				    }
		}
	}
}
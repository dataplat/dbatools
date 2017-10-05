function Invoke-DbaBalanceDataFiles {
	<#
	
	.SYNOPSIS
		Re-balance data between data files

	.DESCRIPTION
		When you have a large database with a single data file and add another file, SQL Server will only use the new file until it's about the same size.
		You may want to balance the data between all the data files.

		The command will check the server version and edition to see if the it allows for online index rebuilds.
		If the server does support it, it will try to rebuild the index online.
		If the server doesn't support it, it will rebuild the index offline. Be carefull though, this can cause downtime

		The tables must have a clustered index to be able to balance out the data.
		The command does NOT yet support heaps.

	.PARAMETER SqlInstance
		The SQL Server instance hosting the databases to be backed up.

	.PARAMETER SqlCredential
		Credentials to connect to the SQL Server instance if the calling user doesn't have permission.

	.PARAMETER Database
		The database(s) to process. 

	.PARAMETER Table
		The tables(s) of the database to process. If unspecified, all tables will be processed.

	.PARAMETER OfflineRebuild
		Will set all the indexes to rebuild offline.
		This option is also needed when the server version is below 2005.

	.PARAMETER Silent
		If this switch is enabled, the internal messaging functions will be silenced.

	.NOTES 
		Original Author: Sander Stad (@sqlstad, sqlstad.nl)
		Tags: Database, File management, data management
			
		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.EXAMPLE 
	Invoke-DbaBalanceDataFiles -SqlInstance sql1 -Database db1
	
	This command will distribute the data in database db1 on instance sql1

	.EXAMPLE
	Invoke-DbaBalanceDataFiles -SqlInstance sql1 -Database db1 -Table table1,table2,table5

	This command will distribute the data for only the tables table1,table2 and table5

	.EXAMPLE
	Invoke-DbaBalanceDataFiles -SqlInstance sql1 -Database db1 -RebuildOffline

	This command will consider the fact that there might be a SQL Server edition that does not support online rebuilds of indexes.
	By supplying this parameter you give permission to do the rebuilds offline if the edition does not support it.

#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]

	param (
		[parameter(ParameterSetName = "Pipe", Mandatory = $true)]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[Alias("Tables")]
		[object[]]$Table,
		[switch]$RebuildOffline,
		[switch]$Silent
	)

	begin {
		Write-Message -Message "Starting balancing out data files" -Level Output

		# Try connecting to the instance
		Write-Message -Message "Attempting to connect to $SqlInstance" -Level Verbose
		try {
			$Server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
		}
		catch {
			Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -Continue
		}

		# Check the database parameter
		if ($Database) {
			if ($Database -notin $server.Databases.Name) {
				Stop-Function -Message "One or more databases cannot be found on instance on instance $SqlInstance" -Target $SqlInstance -Continue
			}

			$DatabaseCollection = $server.Databases | Where-Object { $_.Name -in $Database }
		}
		else {
			Stop-Function -Message "Please supply a database to balance out" -Target $SqlInstance -Continue
		}

		# Get the server version
		$serverVersion = $server.Version.Major

		# Check edition of the sql instance
		if ($RebuildOffline) {
			Write-Message -Message "Continuing with offline rebuild." -Level Verbose
		}
		elseif (-not $RebuildOffline -and ($serverVersion -lt 9 -or (([string]$Server.Edition -notlike "Developer*") -and ($Server.Edition -notlike "Enterprise*")))) {
			# Set up the confirm part
			$message = "The server does not support online rebuilds of indexes. `nDo you want to rebuild the indexes offline?"
			$choiceYes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Answer Yes."
			$choiceNo = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Answer No."
			$options = [System.Management.Automation.Host.ChoiceDescription[]]($choiceYes, $choiceNo)
			$result = $host.ui.PromptForChoice($title, $message, $options, 0)

			# Check the result from the confirm
			switch ($result) {
				# If yes
				0 {
					# Set the option to generate a full backup
					Write-Message -Message "Continuing with offline rebuild." -Level Verbose

					[bool]$supportOnlineRebuild = $false
				}
				1 {
					Stop-Function -Message "You chose to not allow offline rebuilds of indexes. Use -RebuildOffline" -Target $DestinationSqlInstance
					return
				} 
			} # switch
		}
		elseif ($serverVersion -ge 9 -and (([string]$Server.Edition -like "Developer*") -or ($Server.Edition -like "Enterprise*"))) {
			[bool]$supportOnlineRebuild = $true
		}
		
	}

	process {

		if (Test-FunctionInterrupt) { return }

		# Loop through each of the databases
		foreach ($db in $DatabaseCollection) {

			Write-Message -Message "Processing database $db" -Level Output

			# Check the datafiles of the database
			$dataFiles = Get-DbaDatabaseFile -SqlInstance $SqlInstance -Database $db | Where-Object {$_.TypeDescription -eq 'ROWS'}
			if ($dataFiles.Count -eq 1) {
				Stop-Function -Message "Database $db only has one data file. Please add a data file to balance out the data" -Target $SqlInstance -Continue
			}

			# Check the tables parameter
			if ($Table) {
				if ($Table -notin $db.Table) {
					Stop-Function -Message "One or more tables cannot be found in database $db on instance $SqlInstance" -Target $SqlInstance -Continue
				}

				$TableCollection = $db.Tables | Where-Object { $_.Name -in $Table }
			}
			else {
				$TableCollection = $db.Tables 
			}

			# Loop through each of the tables
			foreach ($tbl in $TableCollection) {

				Write-Message -Message "Processing table $tbl" -Level Verbose

				# Chck the tables and get the clustered indexes
				if ($TableCollection.Indexes.Count -lt 1) {
					Stop-Function -Message "Table $tbl does not contain any indexes" -Target $SqlInstance -Continue
				}
				else {

					# Get all the clustered indexes for the table
					$clusteredIndexes = $TableCollection.Indexes | Where-Object {$_.IndexType -eq 'ClusteredIndex'}

					if ($clusteredIndexes.Count -lt 1) {
						Stop-Function -Message "No clustered indexes found in table $tbl" -Target $SqlInstance -Continue
					}
				} 

				# Loop through each of the clustered indexes and rebuild them
				Write-Message -Message "$($clusteredIndexes.Count) clustered index(es) found for table $tbl" -Level Output
				if ($PSCmdlet.ShouldProcess("Rebuilding indexes to balance data")) {
					foreach ($ci in $clusteredIndexes) {
					
						Write-Message -Message "Rebuilding index $($ci.Name)" -Level Output

						# Get the original index operation
						[bool]$originalIndexOperation = $ci.OnlineIndexOperation

						# Set the rebuild option to be either offline or online
						if ($RebuildOffline) {
							$ci.OnlineIndexOperation = $false
						}
						elseif ($serverVersion -ge 9 -and $supportOnlineRebuild -and -not $RebuildOffline) {
							Write-Message -Message "Setting the index operation for index $($ci.Name) to online" -Level Verbose
							$ci.OnlineIndexOperation = $true
						}

						# Rebuild the index
						try {
							$ci.Rebuild()
						}
						catch {
							# Set the original index operation back for the index
							$ci.OnlineIndexOperation = $originalIndexOperation

							Stop-Function -Message "Something went wrong rebuilding index $($ci.Name). `n$($_.Exception.Message)" -ErrorRecord $_ -Target $SqlInstance -Continue
						}

						# Set the original index operation back for the index
						Write-Message -Message "Setting the index operation for index $($ci.Name) back to the original value" -Level Verbose
						$ci.OnlineIndexOperation = $originalIndexOperation
						
					}
				}

			} #foreach table		

		} # foreach database

	} # end process

	end {
		Write-Message -Message "Finished balancing out data files" -Level Output
	}
}
function Set-DbaMaxDop {
	<# 
        .SYNOPSIS 
            Sets SQL Server maximum degree of parallelism (Max DOP), then displays information relating to SQL Server Max DOP configuration settings. Works on SQL Server 2005 and higher.

        .DESCRIPTION 
            Uses the Test-DbaMaxDop command to get the recommended value if -MaxDop parameter is not specified.

            These are just general recommendations for SQL Server and are a good starting point for setting the "max degree of parallelism" option.

            You can set MaxDop database scoped configurations if the server is version 2016 or higher

 		.PARAMETER SqlInstance
			The SQL Server instance to connect to.

        .PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Database
            Specifies one or more databases to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            Specifies one or more databases to exclude from processing. Options for this list are auto-populated from the server

        .PARAMETER MaxDop
            Specifies the Max DOP value to set.

        .PARAMETER AllDatabases
            If this switch is enabled, Max DOP will be set on all databases. This switch is only useful on SQL Server 2016 and higher.

        .PARAMETER Collection
            If Test-SQLMaxDop has been executed prior to this function, the results may be passed in via this parameter.
        
        .PARAMETER WhatIf
			If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

		.PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .NOTES 
            Tags:
            Author: Claudio Silva (@claudioessilva)
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK 
            https://dbatools.io/Set-DbaMaxDop

        .EXAMPLE   
            Set-DbaMaxDop -SqlInstance sql2008, sql2012

            Sets Max DOP to the recommended value for servers sql2008 and sql2012.

        .EXAMPLE 
            Set-DbaMaxDop -SqlInstance sql2014 -MaxDop 4

            Sets Max DOP to 4 for server sql2014.

        .EXAMPLE 
            Test-DbaMaxDop -SqlInstance sql2008 | Set-DbaMaxDop 

            Gets the recommended Max DOP from Test-DbaMaxDop and applies it to to sql2008.

        .EXAMPLE 
            Set-DbaMaxDop -SqlInstance sql2016 -Database db1

            Set recommended Max DOP for database db1 on server sql2016.

        .EXAMPLE 
            Set-DbaMaxDop -SqlInstance sql2016 -AllDatabases

            Set recommended Max DOP for all databases on server sql2016.

    #>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential]$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase,
		[int]$MaxDop = -1,
		[Parameter(ValueFromPipeline = $True)]
		[object]$Collection,
		[Alias("All")]
		[switch]$AllDatabases
	)

	begin {
		if ($Database -and $AllDatabases -and $ExcludeDatabase) {
			throw "-Database, -AllDatabases and -ExcludeDatabase are mutually exclusive. Please choose only one. Quitting."
		}
		
		$processed = New-Object System.Collections.ArrayList
		$results = @()
	}
	process {
		$dbscopedconfiguration = $false
		
		if ($MaxDop -eq -1) {
			$UseRecommended = $true
		}
		
		if ($collection -eq $null) {
			$collection = Test-DbaMaxDop -SqlInstance $sqlinstance -SqlCredential $SqlCredential -Verbose:$false
		}
		elseif ($collection.Instance -eq $null) {
			$collection = Test-DbaMaxDop -SqlInstance $sqlinstance -SqlCredential $SqlCredential -Verbose:$false
		}
		
		$collection | Add-Member -Force -NotePropertyName OldInstanceMaxDopValue -NotePropertyValue 0
		$collection | Add-Member -Force -NotePropertyName OldDatabaseMaxDopValue -NotePropertyValue 0
		
		$servers = $collection | Select-Object Instance -Unique
		
		foreach ($server in $servers) {
			if ($server.Instance -ne $null) {
				$servername = $server.Instance
			}
			else {
				$servername = $server
			}
			
			Write-Verbose "Attempting to connect to $servername"
			try {
				$server = Connect-SqlInstance -SqlInstance $servername -SqlCredential $SqlCredential
			}
			catch {
				Write-Warning "Can't connect to $server or access denied. Skipping."
				continue
			}
			
			if (!(Test-SqlSa -SqlInstance $server)) {
				Write-Error "Not a sysadmin on $server. Skipping."
				$server.ConnectionContext.Disconnect()
				continue
			}
			
			if ($server.versionMajor -ge 13) {
				
				Write-Verbose "Server '$servername' supports Max DOP configuration per database."
				
				if (!$Database -and !$ExcludeDatabase) {
					#Set at instance level
					$collection = $collection | Where-Object { $_.DatabaseMaxDop -eq "N/A" }
				}
				else {
					$dbscopedconfiguration = $true
					
					if (!$AllDatabases -and $Database) {
						
						$collection = $collection | Where-Object { $_.Database -in $Database }
					}
					elseif (!$AllDatabases -and $ExcludeDatabase) {
						$collection = $collection | Where-Object { $_.Database -notin $ExcludeDatabase }
					}
					else {
						if ($AllDatabases) {
							$collection = $collection | Where-Object { $_.DatabaseMaxDop -ne "N/A" }
						}
						else {
							$collection = $collection | Where-Object { $_.DatabaseMaxDop -eq "N/A" }
							$dbscopedconfiguration = $false
						}
					}
				}
			}
			else {
				if ($database -or $AllDatabases) {
					Write-Warning "Server '$servername' (v$($server.versionMajor)) does not support Max DOP configuration at the database level. Remember that this option is only available from SQL Server 2016 (v13). Run the command again without using database related parameters. Skipping."
					Continue
				}
			}
			
			foreach ($row in $collection | Where-Object { $_.Instance -eq $servername }) {
				if ($UseRecommended -and ($row.RecommendedMaxDop -eq $row.CurrentInstanceMaxDop) -and !($dbscopedconfiguration)) {
					Write-Output "$servername is configured properly :) No change required."
					Continue
				}
				
				if ($UseRecommended -and ($row.RecommendedMaxDop -eq $row.DatabaseMaxDop) -and $dbscopedconfiguration) {
					Write-Output "Database $($row.Database) on $servername is configured properly. No change required."
					Continue
				}
				
				$row.OldInstanceMaxDopValue = $row.CurrentInstanceMaxDop
				
				try {
					if ($UseRecommended) {
						if ($dbscopedconfiguration) {
							$row.OldDatabaseMaxDopValue = $row.DatabaseMaxDop
							
							if ($resetDatabases) {
								Write-Verbose "Changing $($row.Database) database max DOP to $($row.DatabaseMaxDop)."
								$server.Databases["$($row.Database)"].MaxDop = $row.DatabaseMaxDop
							}
							else {
								Write-Verbose "Changing $($row.Database) database max DOP from $($row.DatabaseMaxDop) to $($row.RecommendedMaxDop)."
								$server.Databases["$($row.Database)"].MaxDop = $row.RecommendedMaxDop
								$row.DatabaseMaxDop = $row.RecommendedMaxDop
							}
							
						}
						else {
							Write-Verbose "Changing $server SQL Server max DOP from $($row.CurrentInstanceMaxDop) to $($row.RecommendedMaxDop)."
							$server.Configuration.MaxDegreeOfParallelism.ConfigValue = $row.RecommendedMaxDop
							$row.CurrentInstanceMaxDop = $row.RecommendedMaxDop
						}
					}
					else {
						if ($dbscopedconfiguration) {
							$row.OldDatabaseMaxDopValue = $row.DatabaseMaxDop
							
							Write-Verbose "Changing $($row.Database) database max DOP from $($row.DatabaseMaxDop) to $MaxDop."
							$server.Databases["$($row.Database)"].MaxDop = $MaxDop
							$row.DatabaseMaxDop = $MaxDop
						}
						else {
							Write-Verbose "Changing $servername SQL Server max DOP from $($row.CurrentInstanceMaxDop) to $MaxDop."
							$server.Configuration.MaxDegreeOfParallelism.ConfigValue = $MaxDop
							$row.CurrentInstanceMaxDop = $MaxDop
						}
					}
					
					if ($dbscopedconfiguration) {
						if ($Pscmdlet.ShouldProcess($row.Database, "Setting max dop on database")) {
							$server.Databases["$($row.Database)"].Alter()
						}
					}
					else {
						if ($Pscmdlet.ShouldProcess($servername, "Setting max dop on instance")) {
							$server.Configuration.Alter()
						}
					}
					
					$results += [pscustomobject]@{
						ComputerName           = $server.NetName
						InstanceName           = $server.ServiceName
						SqlInstance            = $server.DomainInstanceName
						InstanceVersion        = $row.InstanceVersion
						Database               = $row.Database
						DatabaseMaxDop         = $row.DatabaseMaxDop
						CurrentInstanceMaxDop  = $row.CurrentInstanceMaxDop
						RecommendedMaxDop      = $row.RecommendedMaxDop
						OldDatabaseMaxDopValue = $row.OldDatabaseMaxDopValue
						OldInstanceMaxDopValue = $row.OldInstanceMaxDopValue
					}
				}
				catch { Write-Error "Could not modify Max Degree of Parallelism for $server." }
			}
			
			if ($dbscopedconfiguration) {
				$results | Select-Object Instance, Database, OldDatabaseMaxDopValue, @{ name = "CurrentDatabaseMaxDopValue"; expression = { $_.DatabaseMaxDop } }
			}
			else {
				$results | Select-Object Instance, OldInstanceMaxDopValue, CurrentInstanceMaxDop
			}
		}
	}
}


function Copy-DbaDatabaseAssembly {
	<#
		.SYNOPSIS
			Copy-DbaDatabaseAssembly migrates assemblies from one SQL Server to another.

		.DESCRIPTION
			By default, all assemblies are copied. The -Assemblies parameter is autopopulated for command-line completion and can be used to copy only specific assemblies.

			If the assembly already exists on the destination, it will be skipped unless -Force is used.

			This script does not yet copy dependents.

		.PARAMETER Source
			Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Destination
			Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Assembly
			The assembly(ies) to process - this list is auto populated from the server. If unspecified, all assemblies will be processed.

		.PARAMETER ExcludeAssembly
			The assembly(ies) to exclude - this list is auto populated from the server

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Force
			Drops and recreates the XXXXX if it exists

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, Assembly
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			http://dbatools.io/Get-SqlDatabaseAssembly

		.EXAMPLE
			Copy-DbaDatabaseAssembly -Source sqlserver2014a -Destination sqlcluster

			Copies all assemblies from sqlserver2014a to sqlcluster, using Windows credentials. If assemblies with the same name exist on sqlcluster, they will be skipped.

		.EXAMPLE
			Copy-DbaDatabaseAssembly -Source sqlserver2014a -Destination sqlcluster -Assembly dbname.assemblyname, dbname3.anotherassembly -SourceSqlCredential $cred -Force

			Copies two assemblies, the dbname.assemblyname and dbname3.anotherassembly, from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a assembly with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

			In this example, anotherassembly will be copied to the dbname3 database on the server "sqlcluster".

		.EXAMPLE
			Copy-DbaThing -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

			Shows what would happen if the command were executed using force.
	#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Source,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[object[]]$Assembly,
		[object[]]$ExcludeAssembly,
		[switch]$Force,
		[switch]$Silent
	)
	begin {

		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceServer.DomainInstanceName
		$destination = $destServer.DomainInstanceName

		if ($sourceServer.VersionMajor -lt 9 -or $destServer.VersionMajor -lt 9) {
			throw "Assemblies are only supported in SQL Server 2005 and above. Quitting."
		}
	}
	process {

		$sourceAssemblies = @()
		foreach ($database in $sourceServer.Databases) {
			try {
				# a bug here requires a try/catch
				$userAssemblies = $database.Assemblies | Where-Object IsSystemObject -eq $false
				foreach ($assembly in $userAssemblies) {
					$sourceAssemblies += $assembly
				}
			}
			catch { }
		}

		$destAssemblies = @()
		foreach ($database in $destServer.Databases) {
			try {
				# a bug here requires a try/catch
				$userAssemblies = $database.Assemblies | Where-Object IsSystemObject -eq $false
				foreach ($assembly in $userAssemblies) {
					$destAssemblies += $assembly
				}
			}
			catch { }
		}

		foreach ($currentAssembly in $sourceAssemblies) {
			$assemblyName = $currentAssembly.Name
			$dbName = $currentAssembly.Parent.Name
			$destDb = $destServer.Databases[$dbName]

			$copyDbAssemlbyStatus = [pscustomobject]@{
				SourceServer        = $sourceServer.Name
				SourceDatabase      = $dbName
				DestinationServer   = $destServer.Name
				DestinationDatabase = $destDb
				Name                = $assemblyName
				Status              = $null
				DateTime            = [sqlcollective.dbatools.Utility.DbaDateTime](Get-Date)
			}


			if (!$destDb) {
				$copyDbAssemlbyStatus.Status = "Skipped"
				$copyDbAssemlbyStatus

				Write-Message -Level Warning -Message "Destination database $dbName does not exist. Skipping $assemblyName.";
				continue
			}

			if ($assemblies.length -gt 0 -and $assemblies -notcontains "$dbName.$assemblyName") {
				continue
			}

			if ($currentAssembly.AssemblySecurityLevel -eq "External" -and $destDb.Trustworthy -eq $false) {
				if ($Pscmdlet.ShouldProcess($destination, "Setting $dbName to External")) {
					Write-Message -Level Warning -Message "Setting $dbName Security Level to External on $destination"
					$sql = "ALTER DATABASE $dbName SET TRUSTWORTHY ON"
					try {
						Write-Message -Level Debug -Message $sql
						$destServer.Query($sql)
					}
					catch {
                        $copyDbAssemlbyStatus.Status = "Failed"
                        $copyDbAssemlbyStatus

                        Stop-Function -Message "Issue setting security level" -Target $destDb -InnerErrorRecord $_
					}
				}
			}

			if ($destServer.Databases[$dbName].Assemblies.Name -contains $currentAssembly.name) {
				if ($force -eq $false) {
                    $copyDbAssemlbyStatus.Status = "Skipped"
                    $copyDbAssemlbyStatus

                    Write-Message -Level Warning -Message "Assembly $assemblyName exists at destination in the $dbName database. Use -Force to drop and migrate."
					continue
				}
				else {
					if ($Pscmdlet.ShouldProcess($destination, "Dropping assembly $assemblyName and recreating")) {
						try {
							Write-Message -Level Verbose -Message "Dropping assembly $assemblyName"
							Write-Message -Level Verbose -Message "This won't work if there are dependencies."
							$destServer.Databases[$dbName].Assemblies[$assemblyName].Drop()
							Write-Message -Level Verbose -Message "Copying assembly $assemblyName"
							$sql = $currentAssembly.Script()
							Write-Message -Level Debug -Message $sql
							$destServer.Query($sql,$dbName)
                        }
						catch {
                            $copyDbAssemlbyStatus.Status = "Failed"
                            $copyDbAssemlbyStatus

                            Stop-Function -Message "Issue dropping assembly" -Target $assemblyName -InnerErrorRecord $_ -Continue
						}
					}
				}
			}

			if ($Pscmdlet.ShouldProcess($destination, "Creating assembly $assemblyName")) {
				try {
					Write-Message -Level Verbose -Message "Copying assembly $assemblyName from database."
					$sql = $currentAssembly.Script()
					Write-Message -Level Debug -Message $sql
					$destServer.Query($sql,$dbName)

                    $copyDbAssemlbyStatus.Status = "Successful"
                    $copyDbAssemlbyStatus

                }
				catch {
                    $copyDbAssemlbyStatus.Status = "Failed"
                    $copyDbAssemlbyStatus

                    Stop-Function -Message "Issue creating assembly" -Target $assemblyName -InnerErrorRecord $_
				}
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlDatabaseAssembly
	}
}

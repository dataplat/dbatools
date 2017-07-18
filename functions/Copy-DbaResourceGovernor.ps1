function Copy-DbaResourceGovernor {
	<#
		.SYNOPSIS
			Migrates Resource Pools

		.DESCRIPTION
			By default, all non-system resource pools are migrated. If the pool already exists on the destination, it will be skipped unless -Force is used.

			The -ResourcePool parameter is autopopulated for command-line completion and can be used to copy only specific objects.

		.PARAMETER Source
			Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Destination
			Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER ResourcePool
			The resource pool(s) to process - this list is auto populated from the server. If unspecified, all resource pools will be processed.

		.PARAMETER ExcludeResourcePool
			The resource pool(s) to exclude - this list is auto populated from the server

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Force
			If policies exists on destination server, it will be dropped and recreated.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, ResourceGovernor
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaResourceGovernor

		.EXAMPLE
			Copy-DbaResourceGovernor -Source sqlserver2014a -Destination sqlcluster

			Copies all extended event policies from sqlserver2014a to sqlcluster, using Windows credentials.

		.EXAMPLE
			Copy-DbaResourceGovernor -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

			Copies all extended event policies from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

		.EXAMPLE
			Copy-DbaResourceGovernor -Source sqlserver2014a -Destination sqlcluster -WhatIf

			Shows what would happen if the command were executed.
	#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Source,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SourceSqlCredential = [System.Management.Automation.PSCredential]::Empty,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$DestinationSqlCredential = [System.Management.Automation.PSCredential]::Empty,
		[object[]]$ResourcePool,
		[object[]]$ExcludeResourcePool,
		[switch]$Force,
		[switch]$Silent
	)

	begin {

		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceServer.DomainInstanceName
		$destination = $destServer.DomainInstanceName

		if ($sourceServer.VersionMajor -lt 10 -or $destServer.VersionMajor -lt 10) {
			Stop-Function -Message "Resource Governor is only supported in SQL Server 2008 and above. Quitting."
			return
		}
	}
	process {
		if (Test-FunctionInterrupt) { return }

		$copyResourceGovSetting = [pscustomobject]@{
			SourceServer      = $sourceServer.Name
			DestinationServer = $destServer.Name
			Type              = "Resource Governor Settings"
			Name              = $null
			Status            = $null
			Notes             = $null
			DateTime          = [DbaDateTime](Get-Date)
		}

		if ($Pscmdlet.ShouldProcess($destination, "Updating Resource Governor settings")) {
			if ($destServer.Edition -notmatch 'Enterprise' -and $destServer.Edition -notmatch 'Datacenter' -and $destServer.Edition -notmatch 'Developer') {
				Write-Message -Level Warning -Message "The resource governor is not available in this edition of SQL Server. You can manipulate resource governor metadata but you will not be able to apply resource governor configuration. Only Enterprise edition of SQL Server supports resource governor."
			}
			else {
				try {
					$sql = $sourceServer.ResourceGovernor.Script() | Out-String
					Write-Message -Level Debug -Message $sql
					Write-Message -Level Verbose -Message "Updating Resource Governor settings"
					$destServer.Query($sql)

					$copyResourceGovSetting.Status = "Successful"
					$copyResourceGovSetting
				}
				catch {
					$copyResourceGovSetting.Status = "Failed"
					$copyResourceGovSetting.Notes = $_.Exception
					$copyResourceGovSetting

					Stop-Function -Message "Not able to update settings" -Target $destServer -ErrorRecord $_
				}
			}
		}

		# Pools
		if ($ResourcePool) {
			$pools = $sourceServer.ResourceGovernor.ResourcePools | Where-Object Name -In $ResourcePool
		}
		elseif ($ExcludeResourcePool) {
			$pool = $sourceServer.ResourceGovernor.ResourcePools | Where-Object Name -NotIn $ExcludeResourcePool
		}
		else {
			$pools = $sourceServer.ResourceGovernor.ResourcePools | Where-Object { $_.Name -notin "internal", "default" }
		}

		Write-Message -Level Verbose -Message "Migrating pools"
		foreach ($pool in $pools) {
			$poolName = $pool.Name

			$copyResourceGovPool = [pscustomobject]@{
				SourceServer      = $sourceServer.Name
				DestinationServer = $destServer.Name
				Type              = "Pool"
				Name              = $poolName
				Status            = $null
				Notes             = $null
				DateTime          = [DbaDateTime](Get-Date)
			}

			if ($destServer.ResourceGovernor.ResourcePools[$poolName] -ne $null) {
				if ($force -eq $false) {
					Write-Message -Level Warning -Message "Pool '$poolName' was skipped because it already exists on $destination. Use -Force to drop and recreate"

					$copyResourceGovPool.Status = "Skipped"
					$copyResourceGovPool.Notes = "Already exists on destination"
					$copyResourceGovPool
					continue
				}
				else {
					if ($Pscmdlet.ShouldProcess($destination, "Attempting to drop $poolName")) {
						Write-Message -Level Verbose -Message "Pool '$poolName' exists on $destination"
						Write-Message -Level Verbose -Message "Force specified. Dropping $poolName."

						try {
							$destPool = $destServer.ResourceGovernor.ResourcePools[$poolName]
							$workloadGroups = $destPool.WorkloadGroups
							foreach ($workloadGroup in $workloadGroups) {
								$workloadGroup.Drop()
							}
							$destPool.Drop()
							$destServer.ResourceGovernor.Alter()
						}
						catch {
							$copyResourceGovPool.Status = "Failed to drop from Destination"
							$copyResourceGovPool.Notes = $_.Exception
							$copyResourceGovPool

							Stop-Function -Message "Unable to drop: $_  Moving on." -Target $destPool -ErrorRecord $_ -Continue
						}
					}
				}
			}

			if ($Pscmdlet.ShouldProcess($destination, "Migrating pool $poolName")) {
				try {
					$sql = $pool.Script() | Out-String
					Write-Message -Level Debug -Message $sql
					Write-Message -Level Verbose -Message "Copying pool $poolName"
					$destServer.Query($sql)

					$copyResourceGovPool.Status = "Successful"
					$copyResourceGovPool

					$workloadGroups = $pool.WorkloadGroups
					foreach ($workloadGroup in $workloadGroups) {
						$workgroupName = $workloadGroup.Name

						$copyResourceGovWorkGroup = [pscustomobject]@{
							SourceServer      = $sourceServer.Name
							DestinationServer = $destServer.Name
							Type              = "Pool Workgroup"
							Name              = $workgroupName
							Status            = $null
							Notes             = $null
							DateTime          = [DbaDateTime](Get-Date)
						}

						$sql = $workloadGroup.Script() | Out-String
						Write-Message -Level Debug -Message $sql
						Write-Message -Level Verbose -Message "Copying $workgroupName"
						$destServer.Query($sql)

						$copyResourceGovWorkGroup.Status = "Successful"
						$copyResourceGovWorkGroup
					}
				}
				catch {
					$copyResourceGovWorkGroup.Status = "Failed"
					$copyResourceGovWorkGroup.Notes = $_.Exception
					$copyResourceGovWorkGroup

					Stop-Function -Message "Unable to migrate pool" -Target $pool -ErrorRecord $_
				}
			}
		}

		if ($Pscmdlet.ShouldProcess($destination, "Reconfiguring")) {
			if ($destServer.Edition -notmatch 'Enterprise' -and $destServer.Edition -notmatch 'Datacenter' -and $destServer.Edition -notmatch 'Developer') {
				Write-Message -Level Warning -Message "The resource governor is not available in this edition of SQL Server. You can manipulate resource governor metadata but you will not be able to apply resource governor configuration. Only Enterprise edition of SQL Server supports resource governor."
			}
			else {
				Write-Message -Level Verbose -Message "Reconfiguring Resource Governor"
				$sql = "ALTER RESOURCE GOVERNOR RECONFIGURE"
				$destServer.Query($sql)

				$copyResourceGovReconfig = [pscustomobject]@{
					SourceServer      = $sourceServer.Name
					DestinationServer = $destServer.Name
					Type              = "Reconfigure Resource Governor"
					Name              = $null
					Status            = "Successful"
					Notes             = $null
					DateTime          = [DbaDateTime](Get-Date)
				}
				$copyResourceGovReconfig
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlResourceGovernor
	}
}
function Copy-DbaServerAudit {
	<#
		.SYNOPSIS
			Copy-DbaServerAudit migrates server audits from one SQL Server to another.

		.DESCRIPTION
			By default, all audits are copied. The -Audit parameter is autopopulated for command-line completion and can be used to copy only specific audits.

			If the audit already exists on the destination, it will be skipped unless -Force is used.

		.PARAMETER Source
			Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

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

		.PARAMETER Audit
			The audit(s) to process - this list is auto populated from the server. If unspecified, all audits will be processed.

		.PARAMETER ExcludeAudit
			The audit(s) to exclude - this list is auto populated from the server

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Force
			Drops and recreates the XXXXX if it exists

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaServerAudit

		.EXAMPLE
			Copy-DbaServerAudit -Source sqlserver2014a -Destination sqlcluster

			Copies all server audits from sqlserver2014a to sqlcluster, using Windows credentials. If audits with the same name exist on sqlcluster, they will be skipped.

		.EXAMPLE
			Copy-DbaServerAudit -Source sqlserver2014a -Destination sqlcluster -Audit tg_noDbDrop -SourceSqlCredential $cred -Force

			Copies a single audit, the tg_noDbDrop audit from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If an audit with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

		.EXAMPLE
			Copy-DbaServerAudit -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

			Shows what would happen if the command were executed using force.
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
		[object[]]$Audit,
		[object[]]$ExcludeAudit,
		[switch]$Force,
		[switch]$Silent
	)

	begin {

		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceServer.DomainInstanceName
		$destination = $destServer.DomainInstanceName

		if ($sourceServer.VersionMajor -lt 10 -or $destServer.VersionMajor -lt 10) {
			Stop-Function -Message "Server Audits are only supported in SQL Server 2008 and above. Quitting."
			return
		}

		$serverAudits = $sourceServer.Audits
		$destAudits = $destServer.Audits
	}
	process {
		if (Test-FunctionInterrupt) { return }

		foreach ($currentAudit in $serverAudits) {
			$auditName = $currentAudit.Name

			$copyAuditStatus = [pscustomobject]@{
				SourceServer      = $sourceServer.Name
				DestinationServer = $destServer.Name
				Name              = $auditName
				Type              = $null
				Status            = $null
				Notes             = $null
				DateTime          = [DbaDateTime](Get-Date)
			}

			if ($Audit -and $auditName -notin $Audit -or $auditName -in $ExcludeAudit) {
				continue
			}

			$sql = $currentAudit.Script() | Out-String

			if ($destAudits.Name -contains $auditName) {
				if ($force -eq $false) {
					Write-Message -Level Warning -Message "Server audit $auditName exists at destination. Use -Force to drop and migrate."
					continue
				}
				else {
					if ($Pscmdlet.ShouldProcess($destination, "Dropping server audit $auditName")) {
						try {
							Write-Message -Level Verbose -Message "Dropping server audit $auditName"
							foreach ($spec in $destServer.ServerAuditSpecifications) {
								if ($auditSpecification.Auditname -eq $auditName) {
									$auditSpecification.Drop()
								}
							}

							$destServer.audits[$auditName].Disable()
							$destServer.audits[$auditName].Alter()
							$destServer.audits[$auditName].Drop()
						}
						catch {
							$copyAuditStatus.Status = "Failed"
							$cooyAuditStatus

							Stop-Function -Message "Issue dropping audit from destination" -Target $auditName -ErrorRecord $_
						}
					}
				}
			}

			if ((Test-DbaSqlPath -SqlInstance $destServer -Path $currentAudit.Filepath) -eq $false) {
				if ($Force -eq $false) {
					Write-Message -Level Warning -Message "$($currentAudit.Filepath) does not exist on $destination. Skipping $auditName. Specify -Force to create the directory"

					$copyAuditStatus.Status = "Skipped"
					$copyAuditStatus.Notes = "Already exists on destination"
					$copyAuditStatus
					continue
				}
				else {
					Write-Message -Level Verbose -Message "Force specified. Creating directory."

					$destNetBios = Resolve-NetBiosName $destServer
					$path = Join-AdminUnc $destNetBios $currentAudit.Filepath
					$root = $currentAudit.Filepath.Substring(0, 3)
					$rootUnc = Join-AdminUnc $destNetBios $root

					if ((Test-Path $rootUnc) -eq $true) {
						try {
							if ($Pscmdlet.ShouldProcess($destination, "Creating directory $($currentAudit.Filepath)")) {
								$null = New-Item -ItemType Directory $currentAudit.Filepath -ErrorAction Continue
							}
						}
						catch {
							Write-Message -Level Verbose -Message "Couldn't create directory $($currentAudit.Filepath). Using default data directory."
							$datadir = Get-SqlDefaultPaths $destServer data
							$sql = $sql.Replace($currentAudit.FilePath, $datdir)
						}
					}
					else {
						$datadir = Get-SqlDefaultPaths $destServer data
						$sql = $sql.Replace($currentAudit.FilePath, $datadir)
					}
				}
			}
			if ($Pscmdlet.ShouldProcess($destination, "Creating server audit $auditName")) {
				try {
					Write-Message -Level Verbose -Message "File path $($currentAudit.Filepath) exists on $Destination."
					Write-Message -Level Verbose -Message "Copying server audit $auditName"
					$destServer.Query($sql)

					$copyAuditStatus.Status = "Successful"
					$copyAuditStatus
				}
				catch {
					$copyAuditStatus.Status = "Failed"
					$copyAuditStatus.Notes = $_.Exception
					$copyAuditStatus

					Stop-Function -Message "Issue creating audit" -Target $auditName -ErrorRecord $_
				}
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlAudit
	}
}
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
		$SourceSqlCredential,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$DestinationSqlCredential,
		[object[]]$Audit,
		[object[]]$ExcludeAudit,
		[switch]$Force,
		[switch]$Silent
	)

	begin {

		$sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10) {
			throw "Server Audits are only supported in SQL Server 2008 and above. Quitting."
			
		}
		
		$serveraudits = $sourceserver.Audits
		$destaudits = $destserver.Audits
	}
	process {
		foreach ($audit in $serveraudits) {
			$auditname = $audit.name
			if ($audits.length -gt 0 -and $audits -notcontains $auditname) {
				continue
			}
			
			$sql = $audit.Script() | Out-String
			$sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
			
			if ($destaudits.name -contains $auditname) {
				if ($force -eq $false) {
					Write-Warning "Server audit $auditname exists at destination. Use -Force to drop and migrate."
					continue
				}
				else {
					If ($Pscmdlet.ShouldProcess($destination, "Dropping server audit $auditname")) {
						try {
							Write-Verbose "Dropping server audit $auditname"
							foreach ($spec in $destserver.ServerAuditSpecifications) {
								if ($auditSpecification.Auditname -eq $auditname) {
									$auditSpecification.Drop()
								}
							}
							
							$destserver.audits[$auditname].Disable()
							$destserver.audits[$auditname].Alter()
							$destserver.audits[$auditname].Drop()
						}
						catch { 
							Write-Exception $_ 
						}
					}
				}
			}
			
			if ((Test-DbaSqlPath -SqlInstance $destserver -Path $audit.Filepath) -eq $false) {
				if ($Force -eq $false) {
					Write-Warning "$($audit.Filepath) does not exist on $destination. Skipping $auditname."
					Write-Warning "Specify -Force to create the directory"
					continue
				}
				else {
					Write-Verbose "Force specified. Creating directory."
					
					$destnetbios = Resolve-NetBiosName $destserver
					$path = Join-AdminUnc $destnetbios $audit.Filepath
					$root = $audit.Filepath.Substring(0, 3)
					$rootunc = Join-AdminUnc $destnetbios $root
					
					If ((Test-Path $rootunc) -eq $true) {
						try {
							If ($Pscmdlet.ShouldProcess($destination, "Creating directory $($audit.Filepath)")) {
								$null = New-Item -ItemType Directory $audit.Filepath -ErrorAction Continue
							}
						}
						catch {
							Write-Output "Couldn't create diretory $($audit.Filepath). Using default data directory."
							$datadir = Get-SqlDefaultPaths $destserver data
							$sql = $sql.Replace($audit.FilePath, $datdir)
						}
					}
					else {
						$datadir = Get-SqlDefaultPaths $destserver data
						$sql = $sql.Replace($audit.FilePath, $datadir)
					}
				}
			}
			If ($Pscmdlet.ShouldProcess($destination, "Creating server audit $auditname")) {
				try {
					Write-Output "File path $($audit.Filepath) exists on $Destination."
					Write-Output "Copying server audit $auditname"
					$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
				}
				catch {
					Write-Exception $_
				}
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlAudit
	}
}
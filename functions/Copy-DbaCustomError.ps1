function Copy-DbaCustomError {
	<#
		.SYNOPSIS
			Copy-DbaCustomError migrates custom errors (user defined messages), by the customer error ID, from one SQL Server to another.

		.DESCRIPTION
			By default, all custom errors are copied. The -CustomError parameter is auto-populated for command-line completion and can be used to copy only specific custom errors.

			If the custom error already exists on the destination, it will be skipped unless -Force is used. Interesting fact, if you drop the us_english version, all the other languages will be dropped for that specific ID as well.

			Also, the us_english version must be created first.

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

		.PARAMETER CustomError
			The customer error(s) to process - this list is auto populated from the server. If unspecified, all customer errors will be processed.

		.PARAMETER ExcludeCustomError
			The custom error(s) to exclude - this list is auto populated from the server

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Force
			Drops and recreates the XXXXX if it exists

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, CustomError
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaCustomError

		.EXAMPLE
			Copy-DbaCustomError -Source sqlserver2014a -Destination sqlcluster

			Copies all server custom errors from sqlserver2014a to sqlcluster, using Windows credentials. If custom errors with the same name exist on sqlcluster, they will be skipped.

		.EXAMPLE
			Copy-DbaCustomError -Source sqlserver2014a -SourceSqlCredential $scred -Destination sqlcluster -DestinationSqlCredential $dcred -CustomError 60000 -Force

			Copies a single custom error, the custom error with ID number 60000 from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a custom error with the same name exists on sqlcluster, it will be updated because -Force was used.

		.EXAMPLE
			Copy-DbaCustomError -Source slserver2014a -Destination sqlcluster -ExcludeCustomError 60000 -Force

			Copies all the custom errors found on sqlserver2014a, except the custom error with ID number 60000,to sqlcluster. If a custom error with the same name exists on sqlcluster, it will be updated because -Force was used.

		.EXAMPLE
			Copy-DbaCustomError -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

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
		[object[]]$CustomError,
		[object[]]$ExcludeCustomError,
		[switch]$Force,
		[switch]$Silent
	)

	begin {

		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceServer.DomainInstanceName
		$destination = $destServer.DomainInstanceName

		if ($sourceServer.VersionMajor -lt 9 -or $destServer.VersionMajor -lt 9) {
			throw "Custom Errors are only supported in SQL Server 2005 and above. Quitting."
		}
	}
	process {

		# US has to go first
		$orderedCustomErrors = @($sourceServer.UserDefinedMessages | Where-Object Language -eq "us_english")
		$orderedCustomErrors += $sourceServer.UserDefinedMessages | Where-Object Language -ne "us_english"
		$destCustomErrors = $destServer.UserDefinedMessages

		foreach ($currentCustomError in $orderedCustomErrors) {
			$customErrorId = $currentCustomError.ID
			$language = $currentCustomError.Language.ToString()

			$copyCustomErrorStatus = [pscustomobject]@{
				SourceServer        = $sourceServer.Name
				DestinationServer   = $destServer.Name
				Name                = $currentCustomError
				Status              = $null
				DateTime            = [DbaDateTime](Get-Date)
			}

			if ( $CustomError -and ($customErrorId -notin $CustomError -or $customErrorId -in $ExcludeCustomError) ) {
				continue
			}

			if ($destCustomErrors.ID -contains $customErrorId) {
				if ($force -eq $false) {
					$copyCustomErrorStatus.Status = "Skipped"
					$copyCustomErrorStatus

					Write-Message -Level Warning -Message "Custom error $customErrorId $language exists at destination. Use -Force to drop and migrate."
					continue
				}
				else {
					If ($Pscmdlet.ShouldProcess($destination, "Dropping custom error $customErrorId $language and recreating")) {
						try {
							Write-Message -Level Verbose -Message "Dropping custom error $customErrorId (drops all languages for custom error $customErrorId)"
							$destServer.UserDefinedMessages[$customErrorId, $language].Drop()
						}
						catch {
							$copyCustomErrorStatus.Status = "Failed"
							$copyCustomErrorStatus

							Stop-Function -Message "Issue dropping customer error" -Target $customErrorId -InnerErrorRecord $_ -Continue
						}
					}
				}
			}

			if ($Pscmdlet.ShouldProcess($destination, "Creating custom error $customErrorId $language")) {
				try {
					Write-Message -Level Verbose -Message "Copying custom error $customErrorId $language"
					$sql = $currentCustomError.Script() | Out-String
					Write-Message -Level Debug -Message $sql
					$destServer.Query($sql)

					$copyCustomErrorStatus.Status = "Successful"
					$copyCustomErrorStatus
				}
				catch {
					$copyCustomErrorStatus.Status = "Failed"
					$copyCustomErrorStatus

					Stop-Function -Message "Issue creating custom error" -Target $customErrorId -InnerErrorRecord $_
				}
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlCustomError
	}
}

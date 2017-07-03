function Copy-DbaSqlServerAgent {
	<#
		.SYNOPSIS
			Copy SQL Server Agent from one server to another.

		.DESCRIPTION
			A wrapper function that calls the associated Copy command for the objects under SQL Server Agent in SSMS.
			As well as the SQL Agent properties (job history max rows, DBMail profile name, etc.).

			Copies *all of it*.

			You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER Source
			Source SQL Server.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Destination
			Destination Sql Server.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER DisableJobsOnDestination
			When this flag is set, copy all jobs as Enabled=0

		.PARAMETER DisableJobsOnSource
			Disables the jobs on source

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Force
			Drops and recreates the objects if it exists

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, SqlServerAgent, SqlAgent
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaSqlServerAgent

		.EXAMPLE
			Copy-DbaSqlServerAgent -Source sqlserver2014a -Destination sqlcluster

			Copies all job server objects from sqlserver2014a to sqlcluster, using Windows credentials. If job objects with the same name exist on sqlcluster, they will be skipped.

		.EXAMPLE
			Copy-DbaSqlServerrAgent -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

			Copies all job objects from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

		.EXAMPLE
			Copy-DbaSqlServerAgent -Source sqlserver2014a -Destination sqlcluster -WhatIf

			Shows what would happen if the command were executed.
	#>
	[cmdletbinding(SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Source,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SourceSqlCredential,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$DestinationSqlCredential,
		[Switch]$DisableJobsOnDestination,
		[Switch]$DisableJobsOnSource,
		[switch]$Force,
		[switch]$Silent
	)

	BEGIN {
		$sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		Invoke-SmoCheck -SqlInstance $sourceserver
		Invoke-SmoCheck -SqlInstance $destserver

		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName

		$sourceagent = $sourceserver.jobserver
	}

	PROCESS {

		# All of these support whatif inside of them
		Copy-DbaAgentCategory -Source $sourceserver -Destination $destserver -Force:$force
		Copy-DbaAgentOperator -Source $sourceserver -Destination $destserver -Force:$force
		Copy-DbaAgentAlert -Source $sourceserver -Destination $destserver -Force:$force -IncludeDefaults
		Copy-DbaAgentProxyAccount -Source $sourceserver -Destination $destserver -Force:$force
		Copy-DbaAgentSharedSchedule -Source $sourceserver -Destination $destserver -Force:$force
		Copy-DbaAgentJob -Source $sourceserver -Destination $destserver -Force:$force -DisableOnDestination:$DisableJobsOnDestination -DisableOnSource:$DisableJobsOnSource

		# To do
		<#
			Copy-DbaAgentMasterServer -Source $sourceserver -Destination $destserver -Force:$force
			Copy-DbaAgentTargetServer -Source $sourceserver -Destination $destserver -Force:$force
			Copy-DbaAgentTargetServerGroup -Source $sourceserver -Destination $destserver -Force:$force
		#>

		# Here are the properties, which must be migrated seperately
		If ($Pscmdlet.ShouldProcess($destination, "Copying Agent Properties")) {
			try {
				Write-Output "Copying SQL Agent Properties"
				$sql = $sourceagent.Script() | Out-String
				$sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
				$sql = $sql -replace [Regex]::Escape("@errorlog_file="), [Regex]::Escape("--@errorlog_file=")
				Write-Verbose $sql
				$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
			}
			catch {
				Write-Exception $_
			}
		}
	}

	END {
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Job server migration finished" }
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlServerAgent
	}
}

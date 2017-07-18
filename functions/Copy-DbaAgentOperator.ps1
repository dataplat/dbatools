function Copy-DbaAgentOperator {
	<#
		.SYNOPSIS 
			Copy-DbaAgentOperator migrates operators from one SQL Server to another. 

		.DESCRIPTION
			By default, all operators are copied. The -Operators parameter is autopopulated for command-line completion and can be used to copy only specific operators.

			If the associated credentials for the operator do not exist on the destination, it will be skipped. If the operator already exists on the destination, it will be skipped unless -Force is used.  

		.PARAMETER Source
			Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER Destination
			Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter. 

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	

			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Operator
			The operator(s) to process - this list is autopopulated from the server. If unspecified, all operators will be processed.

		.PARAMETER ExcludeOperator
			The operators(s) to exclude - this list is autopopulated from the server.

		.PARAMETER WhatIf 
			Shows what would happen if the command were to run. No actions are actually performed. 

		.PARAMETER Confirm 
			Prompts you for confirmation before executing any changing operations within the command. 

		.PARAMETER Force
			Drops and recreates the Operator if it exists

		.PARAMETER Silent 
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, Agent, Operator
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaAgentOperator

		.EXAMPLE   
			Copy-DbaAgentOperator -Source sqlserver2014a -Destination sqlcluster

			Copies all operators from sqlserver2014a to sqlcluster, using Windows credentials. If operators with the same name exist on sqlcluster, they will be skipped.

		.EXAMPLE   
			Copy-DbaAgentOperator -Source sqlserver2014a -Destination sqlcluster -Operator PSOperator -SourceSqlCredential $cred -Force

			Copies a single operator, the PSOperator operator from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If an operator with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

		.EXAMPLE   
			Copy-DbaAgentOperator -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

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
		[object[]]$Operator,
		[object[]]$ExcludeOperator,
		[switch]$Force,
		[switch]$Silent
	)

	begin {

		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
		
		$serverOperator = $sourceServer.JobServer.Operators
		$destOperator = $destServer.JobServer.Operators
		
		$failsafe = $destServer.JobServer.AlertSystem | Select-Object FailSafeOperator
	}
	process {

		foreach ($sOperator in $serverOperator) {
			$operatorName = $sOperator.Name
			
			$copyOperatorStatus = [pscustomobject]@{
				SourceServer        = $sourceServer.Name
				DestinationServer   = $destServer.Name
				Name                = $operatorName
				Status              = $null
				DateTime            = [DbaDateTime](Get-Date)
			}
			
			if ($Operator -and $Operator -notcontains $operatorName -or $ExcludeOperator -in $operatorName) {
				continue 
			}
			
			if ($destOperator.Name -contains $sOperator.Name) {
				if ($force -eq $false) {
					$copyOperatorStatus.Status = "Skipped"
					$copyOperatorStatus
					Write-Message -Level Warning -Message "Operator $operatorName exists at destination. Use -Force to drop and migrate."
					continue
				}
				else {
					if ($failsafe.FailSafeOperator -eq $operatorName) {
						Write-Message -Level Warning -Message "$operatorName is the failsafe operator. Skipping drop."
						continue
					}
					
					if ($Pscmdlet.ShouldProcess($destination, "Dropping operator $operatorName and recreating")) {
						try {
							Write-Message -Level Verbose -Message "Dropping Operator $operatorName"
							$destServer.JobServer.Operators[$operatorName].Drop()
						}
						catch {
							$copyOperatorStatus.Status = "Failed"
							$copyOperatorStatus
							
							Stop-Function -Message "Issue dropping operator" -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer -Continue
						}
					}
				}
			}

			if ($Pscmdlet.ShouldProcess($destination, "Creating Operator $operatorName")) {
				try {
					Write-Message -Level Verbose -Message "Copying Operator $operatorName"
					$sql = $sOperator.Script() | Out-String
					Write-Message -Level Debug -Message $sql
					$destServer.Query($sql)
					
					$copyOperatorStatus.Status = "Successful"
					$copyOperatorStatus
				}
				catch {
					$copyOperatorStatus.Status = "Failed"
					$copyOperatorStatus
					Stop-Function -Message "Issue creating operator." -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer
				}
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlOperator
	}
}

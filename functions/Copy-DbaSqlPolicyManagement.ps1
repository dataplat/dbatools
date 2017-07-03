function Copy-DbaSqlPolicyManagement {
	<#
		.SYNOPSIS
			Migrates SQL Policy Based Management Objects, including both policies and conditions.

		.DESCRIPTION
			By default, all policies and conditions are copied. If an object already exist on the destination, it will be skipped unless -Force is used. 
				
			The -Policy and -Condition parameters are autopopulated for command-line completion and can be used to copy only specific objects.

		.PARAMETER Source
			Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2008 or higher.

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

		.PARAMETER Policy
			The policy(ies) to process - this list is auto populated from the server. If unspecified, all policies will be processed.

		.PARAMETER ExcludePolicy
			The policy(ies) to exclude - this list is auto populated from the server

		.PARAMETER Condition
			The condition(s) to process - this list is auto populated from the server. If unspecified, all conditions will be processed.

		.PARAMETER ExcludeCondition
			The condition(s) to exclude - this list is auto populated from the server

		.PARAMETER Force
			If policies exists on destination server, it will be dropped and recreated.

		.PARAMETER WhatIf 
			Shows what would happen if the command were to run. No actions are actually performed. 

		.PARAMETER Confirm 
			Prompts you for confirmation before executing any changing operations within the command. 

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
			https://dbatools.io/Copy-DbaSqlPolicyManagement 

		.EXAMPLE   
			Copy-DbaSqlPolicyManagement -Source sqlserver2014a -Destination sqlcluster

			Copies all policies and conditions from sqlserver2014a to sqlcluster, using Windows credentials. 

		.EXAMPLE   
			Copy-DbaSqlPolicyManagement -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

			Copies all policies and conditions from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

		.EXAMPLE   
			Copy-DbaSqlPolicyManagement -Source sqlserver2014a -Destination sqlcluster -WhatIf

			Shows what would happen if the command were executed.
			
		.EXAMPLE   
			Copy-DbaSqlPolicyManagement -Source sqlserver2014a -Destination sqlcluster -Policy 'xp_cmdshell must be disabled'

			Copies only one policy, 'xp_cmdshell must be disabled' from sqlserver2014a to sqlcluster. No conditions are migrated.
	#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Source,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[switch]$Force
	)

	begin {
		if ([System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Dmf") -eq $null) {
			throw "SMO version is too old. To migrate Policies, you must have SQL Server Management Studio 2008 R2 or higher installed."
		}
		
		$sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName

		if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10) {
			throw "Policy Management is only supported in SQL Server 2008 and above. Quitting."
		}
		
	}
	process {

		$sourceSqlConn = $sourceserver.ConnectionContext.SqlConnectionObject
		$sourceSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sourceSqlConn
		$sourceStore = New-Object  Microsoft.SqlServer.Management.DMF.PolicyStore $sourceSqlStoreConnection
		
		$destSqlConn = $destserver.ConnectionContext.SqlConnectionObject
		$destSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $destSqlConn
		$destStore = New-Object  Microsoft.SqlServer.Management.DMF.PolicyStore $destSqlStoreConnection
		
		$storepolicies = $sourceStore.policies | Where-Object { $_.IsSystemObject -eq $false }
		$storeconditions = $sourceStore.conditions | Where-Object { $_.IsSystemObject -eq $false }
		
		if ($Policy.length -gt 0) { $storepolicies = $storepolicies | Where-Object { $Policy -contains $_.Name } }
		if ($Condition.length -gt 0) { $storeconditions = $storeconditions | Where-Object { $Condition -contains $_.Name } }
		
		if ($Policy.length -gt 0 -and $Condition.length -eq 0) { $storeconditions = $null }
		if ($Condition.length -gt 0 -and $Policy.length -eq 0) { $storepolicies = $null }
		
		<# 
						Conditions
		#>
		
		Write-Output "Migrating conditions"
		foreach ($condition in $storeconditions) {
			$conditionName = $condition.name
			if ($deststore.conditions[$conditionName] -ne $null) {
				if ($force -eq $false) {
					Write-Warning "condition '$conditionName' was skipped because it already exists on $destination"
					Write-Warning "Use -Force to drop and recreate"
					continue
				}
				else {
					if ($Pscmdlet.ShouldProcess($destination, "Attempting to drop $conditionName")) {
						Write-Verbose "Condition '$conditionName' exists on $destination"
						Write-Verbose "Force specified. Dropping $conditionName."
						
						try {
							$dependentpolicies = $deststore.conditions[$conditionName].EnumDependentPolicies()
							foreach ($dependent in $dependentpolicies) {
								$dependent.Drop()
								$deststore.conditions.Refresh()
							}
							$deststore.conditions[$conditionName].Drop()
						}
						catch {
							Write-Exception $_
							continue
						}
					}
				}
			}
			
			if ($Pscmdlet.ShouldProcess($destination, "Migrating condition $conditionName")) {
				try {
					$sql = $condition.ScriptCreate().GetScript() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
					Write-Verbose $sql
					Write-Output "Copying condition $conditionName"
					$null = $destserver.ConnectionContext.ExecuteNonQuery($sql)
					$deststore.Conditions.Refresh()
				}
				catch {
					Write-Exception $_
				}
			}
		}
		
		<# 
						Policies
		#>
		
		Write-Output "Migrating policies"
		foreach ($policy in $storepolicies) {
			$policyName = $policy.name
			if ($deststore.policies[$policyName] -ne $null) {
				if ($force -eq $false) {
					Write-Warning "Policy '$policyName' was skipped because it already exists on $destination"
					Write-Warning "Use -Force to drop and recreate"
					continue
				}
				else {
					if ($Pscmdlet.ShouldProcess($destination, "Attempting to drop $policyName")) {
						Write-Verbose "Policy '$policyName' exists on $destination"
						Write-Verbose "Force specified. Dropping $policyName."
						
						try {
							$deststore.policies[$policyName].Drop()
							$deststore.policies.refresh()
						}
						catch {
							Write-Exception $_
							continue
						}
					}
				}
			}
			
			if ($Pscmdlet.ShouldProcess($destination, "Migrating policy $policyName")) {
				try {
					$deststore.conditions.Refresh()
					$deststore.policies.Refresh()
					$sql = $policy.ScriptCreateWithDependencies().GetScript() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
					Write-Verbose $sql
					Write-Output "Copying policy $policyName"
					$null = $destserver.ConnectionContext.ExecuteNonQuery($sql)
				}
				catch {
					# This is usually because of a duplicate dependent from above. Just skip for now.
					# Write-Exception $_
				}
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlPolicyManagement
	}
}

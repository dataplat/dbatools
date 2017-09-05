Function Get-DbaPolicy {
<#
	.SYNOPSIS
	Returns polices from policy based management from an instance.

	.DESCRIPTION
	Returns details of policies with the option to filter on Category and SystemObjects.

	.PARAMETER SqlInstance
	SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
	
	.PARAMETER SqlCredential
	SqlCredential object to connect as. If not specified, current Windows login will be used.

	.PARAMETER Category
	Filters results to only show policies in the category selected

	.PARAMETER IncludeSystemObject
	By default system objects are filtered out. Use this parameter to INCLUDE them .

	.PARAMETER Silent
	If this switch is enabled, the internal messaging functions will be silenced. 

	.NOTES
	Original Author: Stephen Bennett (https://sqlnotesfromtheunderground.wordpress.com/)
	Tags: Policy, PoilcyBasedManagement

	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Get-DbaPolicy 

	.EXAMPLE   
	Get-DbaPolicy -SqlInstance sql2016

	Returns all policies from sql2016 server

	.EXAMPLE   
	Get-DbaPolicy -SqlInstance sql2016 -SqlCredential $cred

	Uses a credential $cred to connect and return all policies from sql2016 instance

	.EXAMPLE   
	Get-DbaPolicy -SqlInstance sql2016 -Category MorningCheck

	Returns all policies from sql2016 server that part of the PolicyCategory MorningCheck
#>
	[CmdletBinding()]
	param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[string]$Category,
		[switch]$IncludeSystemObject,
		[switch]$Silent
	)
	
	process {
		foreach ($instance in $SqlInstance) {
			Write-Message -Level Verbose -Message "Attempting to connect to $instance"
			
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			$sqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $server.ConnectionContext.SqlConnectionObject
			
			# DMF is the Declarative Management Framework, Policy Based Management's old name
			$store = New-Object Microsoft.SqlServer.Management.DMF.PolicyStore $sqlStoreConnection
			
			$allpolicies = $store.Policies
			
			if (!$IncludeSystemObject) {
				$allpolicies = $allpolicies | Where-Object { $_.IsSystemObject -eq 0 }
			}
			
			if ($Category) {
				$allpolicies = $allpolicies | Where-Object { $_.PolicyCategory -eq $Category }
			}
			
			foreach ($policy in $allpolicies) {
				Write-Message -Level Verbose -Message "Processing $policy"
				Add-Member -Force -InputObject $policy -MemberType NoteProperty ComputerName -value $server.NetName
				Add-Member -Force -InputObject $policy -MemberType NoteProperty InstanceName -value $server.ServiceName
				Add-Member -Force -InputObject $policy -MemberType NoteProperty SqlInstance -value $server.DomainInstanceName
				
				# Select all of the columns you'd like to show
				Select-DefaultView -InputObject $policy -Property ComputerName, InstanceName, SqlInstance, Name, PolicyCategory, Condition, Enabled, HelpLink, HelpText, Description
			}
		}
	}
}
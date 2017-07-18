function Get-DbaServerAudit
{
<#
.SYNOPSIS
Gets SQL Security Audit information for each instance(s) of SQL Server.

.DESCRIPTION
 The Get-DbaServerAudit command gets SQL Security Audit information for each instance(s) of SQL Server.

.PARAMETER SqlInstance
SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
to be executed against multiple SQL Server instances.

.PARAMETER Credential
PSCredential object to connect as. If not specified, current Windows login will be used.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages.

.NOTES
Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Get-DbaServerAudit

.EXAMPLE
Get-DbaServerAudit -SqlInstance localhost
Returns all Security Audits on the local default SQL Server instance

.EXAMPLE
Get-DbaServerAudit -SqlInstance localhost, sql2016
Returns all Security Audits for the local and sql2016 SQL Server instances

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$Credential = [System.Management.Automation.PSCredential]::Empty,
		[switch]$Silent
	)
	
	process {
		foreach ($instance in $SqlInstance)
		{
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $Credential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			if ($server.versionMajor -lt 10) {
				Write-Warning "Server Audits are only supported in SQL Server 2008 and above. Quitting."
				continue
			}
			foreach ($audit in $server.Audits) {
				Add-Member -Force -InputObject $audit -MemberType NoteProperty -Name ComputerName -value $audit.Parent.NetName
				Add-Member -Force -InputObject $audit -MemberType NoteProperty -Name InstanceName -value $audit.Parent.ServiceName
				Add-Member -Force -InputObject $audit -MemberType NoteProperty -Name SqlInstance -value $audit.Parent.DomainInstanceName
				
				Select-DefaultView -InputObject $audit -Property ComputerName, InstanceName, SqlInstance, Name, 'Enabled as IsEnabled', FilePath, FileName
			}
			if($server.Audits.Count -eq 0) {
				Write-Message -Level Output -Message "No server audit found on $($server.DomainInstanceName)"
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Get-SqlServerAudit
	}
}

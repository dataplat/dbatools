function Get-DbaComputerCertificate {
<#
.SYNOPSIS
Creates a new computer certificate useful for Forcing Encryption

.DESCRIPTION
Creates a new computer certificate - signed by an Active Directory CA, using the Web Server certificate. Self-signing is not currenty supported but feel free to add it.
	
By default, a key with a length of 1024 and a friendly name of the machines FQDN is generated.
	
This command was originally intended to help automate the process so that SSL certificates can be available for enforcing encryption on connections.
	
It makes a lot of assumptions - namely, that your account is allowed to auto-enroll and that you have permission to do everything it needs to do ;)

References:
http://sqlmag.com/sql-server/7-steps-ssl-encryption
https://azurebi.jppp.org/2016/01/23/using-lets-encrypt-certificates-for-secure-sql-server-connections/
https://blogs.msdn.microsoft.com/sqlserverfaq/2016/09/26/creating-and-registering-ssl-certificates/

The certificate is generated using AD's webserver SSL template on the client machine and pushed to the remote machine.

.PARAMETER ComputerName
The target SQL Server - defaults to localhost. If target is a cluster, you must also specify InstanceClusterName (see below)

.PARAMETER Credential
Allows you to login to $ComputerName using alternative credentials.
	
.PARAMETER FriendlyName
The FriendlyName listed in the certificate. This defaults to the FQDN of the $ComputerName

.PARAMETER InstanceClusterName
When creating certs for a cluster, use this parameter to create the certificate for the cluster node name. Use ComputerName for each of the nodes.

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Certificate

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Get-DbaComputerCertificate
Gets computer certificates on localhost that are candidates for using with SQL Server's network encryption

.EXAMPLE
Get-DbaComputerCertificate -ComputerName

Gets computer certificates on sql2016 that are candidates for using with SQL Server's network encryption


#>
	[CmdletBinding()]
	param (
		[parameter(ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer", "SqlInstance")]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[System.Management.Automation.PSCredential]$Credential,
		[string]$FriendlyName = "SQL Server",
		[string]$Store = "LocalMachine",
		[string]$Folder = "My",
		[switch]$Silent
	)
	
	process {
		foreach ($computer in $computername) {
			
			$scriptblock = {
				Get-ChildItem Cert:\$Store\$Folder -Recurse | Where-Object { $_.DnsNameList -contains "$env:COMPUTERNAME.$env:USERDNSDOMAIN" -and $_.EnhancedKeyUsageList -contains 'Server Authentication (1.3.6.1.5.5.7.3.1)' }
			}
			
			if ($PScmdlet.ShouldProcess("local", "Connecting to $computer")) {
				try {
					Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptblock -ErrorAction Stop
				}
				catch {
					Stop-Function -Message $_ -ErrorRecord $_ -Target $computer -Continue
				}
			}
		}
	}
}
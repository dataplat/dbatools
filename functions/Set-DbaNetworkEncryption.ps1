function Set-DbaNetworkEncryption {
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

.PARAMETER CaServer
Optional - the CA Server where the request will be sent to

.PARAMETER CaName
The properly formatted CA name of the corresponding CaServer

.PARAMETER Password
Password to encrypt/decrypt private key for export to remote machine
	
.PARAMETER FriendlyName
The FriendlyName listed in the certificate. This defaults to the FQDN of the $ComputerName
	
.PARAMETER KeyLength
The length of the key - defaults to 1024
	
.PARAMETER CertificateTemplate
The domain's Certificate Template - WebServer by default.

.PARAMETER InstanceClusterName
When creating certs for a cluster, use this parameter to create the certificate for the cluster node name. Use ComputerName for each of the nodes.
		
.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Certificate

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Set-DbaNetworkEncryption
Creates a computer certificate signed by the local domain CA for the local machine with the keylength of 1024.

.EXAMPLE
Set-DbaNetworkEncryption -ComputerName Server1

Creates a computer certificate signed by the local domain CA _on the local machine_ for server1 with the keylength of 1024. 
	
The certificate is then copied to the new machine over WinRM and imported.

.EXAMPLE
Set-DbaNetworkEncryption -ComputerName sqla, sqlb -InstanceClusterName sqlcluster -KeyLength 4096

Creates a computer certificate for sqlcluster, signed by the local domain CA, with the keylength of 4096. 
	
The certificate is then copied to sqla _and_ sqlb over WinRM and imported.

.EXAMPLE
Set-DbaNetworkEncryption -ComputerName Server1 -WhatIf

Shows what would happen if the command were run

#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low", DefaultParameterSetName = 'Default')]
	param (
		[Alias("ServerInstance", "SqlServer", "ComputerName")]
		[DbaInstanceParameter]$SqlInstance = $env:COMPUTERNAME,
		[System.Management.Automation.PSCredential]$Credential,
		[parameter(Mandatory, ParameterSetName = "Certificate", ValueFromPipeline)]
		[System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
		[parameter(Mandatory, ParameterSetName = "Thumbprint")]
		[string]$Thumbprint,
		[switch]$Silent
	)
	process {
		if ([dbavalidate]::IsLocalhost($sqlinstance)) {
			Test-RunAsAdmin
		}
		
		if (!$Certificate -and !$Thumbprint) {
			Stop-Function -Message "You must specify a certificate or thumbprint"
			return
		}
		
		if (!$Thumbprint) {
			$Thumbprint = $Certificate.Thumbprint
		}
		
		$resolved = Resolve-DbaNetworkName -ComputerName $SqlInstance -Turbo
		
		if ($null -eq $resolved) {
			Stop-Function -Message "Can't resolve $SqlInstance" -Target $resolved
			return
		}
		
		$instance = Invoke-ManagedComputerCommand -Server $resolved.FQDN -ScriptBlock { $wmi.Services } | Where-Object DisplayName -eq "SQL Server ($($SqlInstance.InstanceName))"
		$instanceid = ($instance.AdvancedProperties | Where-Object Name -eq INSTANCEID).Value
		$regroot = ($instance.AdvancedProperties | Where-Object Name -eq REGROOT).Value
		$serviceaccount = $instance.ServiceAccount
		
		if ($null -eq $regroot) {
			Stop-Function -Message "Can't find instance $($SqlInstance.InstanceName) on $env:COMPUTERNAME" -Target $args[0]
			return
		}

		$scriptblock = {
			$cert = Get-ChildItem Cert:\LocalMachine\My -Recurse | Where-Object Thumbprint -eq $args[0]
			if ($null -eq $cert) {
				Stop-Function -Message "Certificate does not exist on $env:COMPUTERNAME" -Target $args[0]
				return
			}
			$serviceaccount = $args[2]
			
			$regpath = 'Registry::HKEY_LOCAL_MACHINE\$regroot\MSSQLServer\SuperSocketNetLib'
			Set-ItemProperty -Path $regpath -Name Certificate -Value $args[1]
		}
		
		if ($PScmdlet.ShouldProcess("local", "Connecting to $ComputerName to import new cert")) {
			try {
				Invoke-Command2 -ComputerName $resolved.fqdn -Credential $Credential -ArgumentList $Thumbprint, $regroot, $serviceaccount -ScriptBlock $scriptblock -ErrorAction Stop
			}
			catch {
				Stop-Function -Message $_ -ErrorRecord $_ -Target $ComputerName -Continue
			}
		}
	}
}
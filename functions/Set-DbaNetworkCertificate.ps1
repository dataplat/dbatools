function Set-DbaNetworkCertificate {
<#
.SYNOPSIS
Sets the network certificate for SQL Server instance

.DESCRIPTION
Sets the network certificate for SQL Server instance. This setting is found in Configuration Manager.

This command also grants read permissions for the service account on the certificate's private key.

References:
http://sqlmag.com/sql-server/7-steps-ssl-encryption
https://azurebi.jppp.org/2016/01/23/using-lets-encrypt-certificates-for-secure-sql-server-connections/
https://blogs.msdn.microsoft.com/sqlserverfaq/2016/09/26/creating-and-registering-ssl-certificates/

.PARAMETER SqlInstance
The target SQL Server - defaults to localhost.

.PARAMETER Credential
Allows you to login to the computer (not sql instance) using alternative credentials.

.PARAMETER Certificate
The target certificate object
	
.PARAMETER Thumbprint
The thumbprint of the target certificate

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
New-DbaComputerCertificate | Set-DbaNetworkCertificate -SqlInstance localhost\SQL2008R2SP2

Creates and imports a new certificate signed by an Active Directory CA on localhost then sets the network certificate for the SQL2008R2SP2 to that newly created certificate.

.EXAMPLE
Set-DbaNetworkCertificate -SqlInstance sql1\SQL2008R2SP2 -Thumbprint 1223FB1ACBCA44D3EE9640F81B6BA14A92F3D6E2

Sets the network certificate for the SQL2008R2SP2 instance to the certificate with the thumbprint of 1223FB1ACBCA44D3EE9640F81B6BA14A92F3D6E2 in LocalMachine\My on sql1

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
			Write-Message -Level Output -Message "Getting thumbprint"
			$Thumbprint = $Certificate.Thumbprint
		}
		
		Write-Message -Level Output -Message "Resolving hostname"
		$resolved = Resolve-DbaNetworkName -ComputerName $SqlInstance -Turbo
		
		if ($null -eq $resolved) {
			Write-Message -Level Warning -Message "Can't resolve $SqlInstance"
			return
		}
		
		Write-Message -Level Output -Message "Connecting to SQL WMI on $($SqlInstance.ComputerName)"
		try {
			$instance = Invoke-ManagedComputerCommand -Server $resolved.FQDN -ScriptBlock { $wmi.Services } -Credential $Credential -ErrorAction Stop | Where-Object DisplayName -eq "SQL Server ($($SqlInstance.InstanceName))"
		}
		catch {
			Stop-Function -Message $_ -Target $instance
			return
		}
		
		$regroot = ($instance.AdvancedProperties | Where-Object Name -eq REGROOT).Value
		$serviceaccount = $instance.ServiceAccount
		
		Write-Message -Level Output -Message "Regroot: $regroot"
		Write-Message -Level Output -Message "ServiceAcct: $serviceaccount"
		
		if ($null -eq $regroot) {
			Write-Message -Level Warning -Message "Can't find instance $($SqlInstance.InstanceName) on $env:COMPUTERNAME"
			return
		}
		
		$scriptblock = {
			$Thumbprint = $args[0];  $regroot = $args[1]
			$serviceaccount = $args[2]; $instancename = $args[3]; $SqlInstance = $args[4]
			$regpath = "Registry::HKEY_LOCAL_MACHINE\$regroot\MSSQLServer\SuperSocketNetLib"
			
			$oldthumbprint = (Get-ItemProperty -Path $regpath -Name Certificate).Certificate
			
			$cert = Get-ChildItem Cert:\LocalMachine\My -Recurse | Where-Object Thumbprint -eq $Thumbprint
			
			if ($null -eq $cert) {
				Write-Warning "Certificate does not exist on $env:COMPUTERNAME"
				return
			}
			
			$permission = $args[2], "Read", "Allow"
			$accessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $permission
			
			$keyPath = $env:ProgramData + "\Microsoft\Crypto\RSA\MachineKeys\"
			$keyName = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
			$keyFullPath = $keyPath + $keyName
			
			$acl = Get-Acl -Path $keyFullPath
			$null = $acl.AddAccessRule($accessRule)
			Set-Acl -Path $keyFullPath -AclObject $acl
			
			if ($acl) {
				Set-ItemProperty -Path $regpath -Name Certificate -Value $Thumbprint
			}
			else {
				Write-Warning "Read-only permissions could not be granted to certificate"
				return
			}
			
			if (![System.String]::IsNullOrEmpty($oldthumbprint)) {
				$notes = "Granted $serviceaccount read access to certificate private key. Replaced thumbprint: $oldthumbprint."
			}
			else {
				$notes = "Granted $serviceaccount read access to certificate private key"
			}
			
			[pscustomobject]@{
				ComputerName = $env:COMPUTERNAME
				InstanceName = $instancename
				SqlInstance = $SqlInstance
				ServiceAccount = $serviceaccount
				CertificateThumbprint = $cert.Thumbprint
				Certificate = $cert
				Notes = $notes
			} | Select-DefaultView -ExcludeProperty Certificate
		}
		
		if ($PScmdlet.ShouldProcess("local", "Connecting to $ComputerName to import new cert")) {
			try {
				Invoke-Command2 -ComputerName $resolved.fqdn -Credential $Credential -ArgumentList $Thumbprint, $regroot, $serviceaccount, $SqlInstance.InstanceName, $SqlInstance -ScriptBlock $scriptblock -ErrorAction Stop
			}
			catch {
				Stop-Function -Message $_ -ErrorRecord $_ -Target $ComputerName -Continue
			}
		}
	}
}
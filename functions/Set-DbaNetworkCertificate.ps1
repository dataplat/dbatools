function Set-DbaNetworkCertificate {
<#
.SYNOPSIS
Sets the network certificate for SQL Server instance

.DESCRIPTION
Sets the network certificate for SQL Server instance

References:
http://sqlmag.com/sql-server/7-steps-ssl-encryption
https://azurebi.jppp.org/2016/01/23/using-lets-encrypt-certificates-for-secure-sql-server-connections/
https://blogs.msdn.microsoft.com/sqlserverfaq/2016/09/26/creating-and-registering-ssl-certificates/

.PARAMETER SqlInstance
The target SQL Server - defaults to localhost. If target is a cluster, you must also specify InstanceClusterName (see below)

.PARAMETER Credential
Allows you to login to the computer (not sql instance) using alternative credentials.

.PARAMETER Certificate
The Certificate object
	
.PARAMETER Thumbprint
The thumbprint 

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

Hello

.EXAMPLE
Set-DbaNetworkCertificate -SqlInstance localhost\SQL2008R2SP2 -Thumbprint 1223FB1ACBCA44D3EE9640F81B6BA14A92F3D6E2 -WhatIf

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
			Write-Message -Level Output -Message "Getting thumbprint"
			$Thumbprint = $Certificate.Thumbprint
		}
		
		Write-Message -Level Output -Message "Resolving hostname"
		$resolved = Resolve-DbaNetworkName -ComputerName $SqlInstance -Turbo
		
		if ($null -eq $resolved) {
			Stop-Function -Message "Can't resolve $SqlInstance" -Target $resolved
			return
		}
		
		Write-Message -Level Output -Message "Getting WMI info"
		$instance = Invoke-ManagedComputerCommand -Server $resolved.FQDN -ScriptBlock { $wmi.Services } | Where-Object DisplayName -eq "SQL Server ($($SqlInstance.InstanceName))"
		$instanceid = ($instance.AdvancedProperties | Where-Object Name -eq INSTANCEID).Value
		$regroot = ($instance.AdvancedProperties | Where-Object Name -eq REGROOT).Value
		$serviceaccount = $instance.ServiceAccount
		
		Write-Message -Level Output -Message "Instanceid: $instanceid"
		Write-Message -Level Output -Message "Regroot: $regroot"
		Write-Message -Level Output -Message "ServiceAcct: $serviceaccount"
		
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
			
			$permission = $args[2], "Read", "Allow"
			$accessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $permission
			
			$keyPath = $env:ProgramData + "\Microsoft\Crypto\RSA\MachineKeys\"
			$keyName = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
			$keyFullPath = $keyPath + $keyName
			
			$acl = Get-Acl -Path $keyFullPath
			$null = $acl.AddAccessRule($accessRule)
			Set-Acl -Path $keyFullPath -AclObject $acl
			
			if ($acl) {
				$regpath = "Registry::HKEY_LOCAL_MACHINE\$regroot\MSSQLServer\SuperSocketNetLib"
				Set-ItemProperty -Path $regpath -Name Certificate -Value $args[1]
			}
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
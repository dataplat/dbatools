function Enable-DbaForceNetworkEncryption {
<#
.SYNOPSIS
Enables Force Encryption for a SQL Server instance

.DESCRIPTION
Enables Force Encryption for a SQL Server instance. Note that this requires access to the Windows Server - not the SQL instance itself.
	
This setting is found in Configuration Manager.

.PARAMETER SqlInstance
The target SQL Server - defaults to localhost.

.PARAMETER Credential
Allows you to login to the computer (not sql instance) using alternative Windows credentials

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command

.PARAMETER Silent 
Use this switch to Enable any kind of verbose messages

.NOTES
Tags: Certificate

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Enable-DbaForceNetworkEncryption
	
Enables Force Encryption on the default (MSSQLSERVER) instance on localhost - requires (and checks for) RunAs admin.

.EXAMPLE
Enable-DbaForceNetworkEncryption -SqlInstance sql01\SQL2008R2SP2

Enables Force Network Encryption for the SQL2008R2SP2 on sql01. Uses Windows Credentials to both login and modify the registry.

.EXAMPLE
Enable-DbaForceNetworkEncryption -SqlInstance sql01\SQL2008R2SP2 -WhatIf

Shows what would happen if the command were executed.
#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low", DefaultParameterSetName = 'Default')]
	param (
		[Alias("ServerInstance", "SqlServer", "ComputerName")]
		[DbaInstanceParameter]$SqlInstance = $env:COMPUTERNAME,
		[System.Management.Automation.PSCredential]$Credential,
		[switch]$Silent
	)
	process {
		if ([dbavalidate]::IsLocalhost($sqlinstance)) {
			Test-RunAsAdmin
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
		Write-Message -Level Output -Message "Regroot: $regroot"
		
		if ($null -eq $regroot) {
			Write-Message -Level Warning -Message "Can't find instance $($SqlInstance.InstanceName) on $env:COMPUTERNAME"
			return
		}
		
		$scriptblock = {
			$regpath = "Registry::HKEY_LOCAL_MACHINE\$($args[0])\MSSQLServer\SuperSocketNetLib"
			$cert = (Get-ItemProperty -Path $regpath -Name Certificate).Certificate
			
			if ([System.String]::IsNullOrEmpty($cert)) {
				throw "Certificate required to force encryption but certificate is not associated with instance"
			}
			
			$oldvalue = (Get-ItemProperty -Path $regpath -Name ForceEncryption).ForceEncryption
			Set-ItemProperty -Path $regpath -Name ForceEncryption -Value $true
			$forceencryption = (Get-ItemProperty -Path $regpath -Name ForceEncryption).ForceEncryption
			
			[pscustomobject]@{
				ComputerName = $env:COMPUTERNAME
				InstanceName = $args[2]
				SqlInstance = $args[1]
				ForceEncryption = ($forceencryption -eq $true)
				CertificateThumbprint = $cert
			}
			
			if ($oldvalue -ne $forceencryption) {
				Write-Warning "Force encryption was successfully set on $env:COMPUTERNAME for the $($args[2]) instance. You must now restart the SQL Server for changes to take effect."
			}
		}
		
		if ($PScmdlet.ShouldProcess("local", "Connecting to $ComputerName to import new cert")) {
			try {
				Invoke-Command2 -ComputerName $resolved.fqdn -Credential $Credential -ArgumentList $regroot, $SqlInstance, $SqlInstance.InstanceName -ScriptBlock $scriptblock -ErrorAction Stop
			}
			catch {
				Stop-Function -Message $_ -ErrorRecord $_ -Target $SqlInstance -Continue
			}
		}
	}
}
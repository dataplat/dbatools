function Remove-DbaNetworkCertificate {
<#
.SYNOPSIS
Removes the network certificate for SQL Server instance

.DESCRIPTION
Removes the network certificate for SQL Server instance. This setting is found in Configuration Manager.

.PARAMETER SqlInstance
The target SQL Server - defaults to localhost. If target is a cluster, you must also specify InstanceClusterName (see below)

.PARAMETER Credential
Allows you to login to the computer (not sql instance) using alternative credentials.

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
Remove-DbaNetworkCertificate

Removes the Network Certificate for the default instance (MSSQLSERVER) on localhost

.EXAMPLE
Remove-DbaNetworkCertificate -SqlInstance sql1\SQL2008R2SP2

Removes the Network Certificate for the SQL2008R2SP2 instance on sql1

.EXAMPLE
Remove-DbaNetworkCertificate -SqlInstance localhost\SQL2008R2SP2 -WhatIf

Shows what would happen if the command were run

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
			Set-ItemProperty -Path $regpath -Name Certificate -Value $null
			
			if (![System.String]::IsNullOrEmpty($cert)) {
				[pscustomobject]@{
					ComputerName = $env:COMPUTERNAME
					InstanceName = $args[2]
					SqlInstance = $args[1]
					CertificateThumbprint = $null
					Notes = "Removed thumbprint: $cert"
				}
			}
			else {
				[pscustomobject]@{
					ComputerName = $env:COMPUTERNAME
					InstanceName = $args[2]
					SqlInstance = $args[1]
					CertificateThumbprint = $null
					Notes = $null
				} | Select-DefaultView -ExcludeProperty Notes
			}			
		}
		
		if ($PScmdlet.ShouldProcess("local", "Connecting to $ComputerName to remove the cert")) {
			try {
				Invoke-Command2 -ComputerName $resolved.fqdn -Credential $Credential -ArgumentList $regroot, $SqlInstance, $SqlInstance.InstanceName -ScriptBlock $scriptblock -ErrorAction Stop
			}
			catch {
				Stop-Function -Message $_ -ErrorRecord $_ -Target $ComputerName -Continue
			}
		}
	}
}
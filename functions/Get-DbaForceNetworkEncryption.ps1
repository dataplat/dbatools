function Get-DbaForceNetworkEncryption {
<#
.SYNOPSIS
Gets Force Encryption for a SQL Server instance

.DESCRIPTION
Gets Force Encryption for a SQL Server instance. Note that this requires access to the Windows Server - not the SQL instance itself.

This setting is found in Configuration Manager.

.PARAMETER ComputerName
The target SQL Server - defaults to localhost.

.PARAMETER Credential
Allows you to login to the computer (not sql instance) using alternative Windows credentials

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command

.PARAMETER Silent 
Use this switch to Get any kind of verbose messages

.NOTES
Tags: Certificate

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Get-DbaForceNetworkEncryption
	
Gets Force Encryption on the default (MSSQLSERVER) instance on localhost - requires (and checks for) RunAs admin.

.EXAMPLE
Get-DbaForceNetworkEncryption -SqlInstance sql01\SQL2008R2SP2

Gets Force Network Encryption for the SQL2008R2SP2 on sql01. Uses Windows Credentials to both login and view the registry.

.EXAMPLE
Get-DbaForceNetworkEncryption -SqlInstance sql01\SQL2008R2SP2 -WhatIf

Shows what would happen if the command were executed.
#>
	[CmdletBinding()]
	param (
		[Alias("ServerInstance", "SqlServer", "SqlInstance")]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$Credential,
		[switch]$Silent
	)
	process {
		foreach ($computer in $ComputerName) {
			Write-Message -Level Verbose -Message "Resolving hostname"
			$resolved = Resolve-DbaNetworkName -ComputerName $Computer -Turbo
			
			if ($null -eq $resolved) {
				Write-Message -Level Warning -Message "Can't resolve $Computer"
				return
			}
			
			Write-Message -Level Verbose -Message "Connecting to SQL WMI on $($Computer.ComputerName)"
			try {
				$instances = Invoke-ManagedComputerCommand -Server $resolved.FQDN -ScriptBlock { $wmi.Services } -Credential $Credential -ErrorAction Stop | Where-Object DisplayName -match "SQL Server \("
			}
			catch {
				Stop-Function -Message $_ -Target $instance
				return
			}
			
			foreach ($sqlwmi in $instances) {
				$regroot = ($sqlwmi.AdvancedProperties | Where-Object Name -eq REGROOT).Value
				$vsname = ($sqlwmi.AdvancedProperties | Where-Object Name -eq VSNAME).Value
				$instancename = $sqlwmi.DisplayName.Replace('SQL Server (', '').Replace(')', '') # Don't clown, I don't know regex :(
				$serviceaccount = $sqlwmi.ServiceAccount
				
				if ([System.String]::IsNullOrEmpty($regroot)) {
					$regroot = $sqlwmi.AdvancedProperties | Where-Object { $_ -match 'REGROOT' }
					$vsname = $sqlwmi.AdvancedProperties | Where-Object { $_ -match 'VSNAME' }
					
					if (![System.String]::IsNullOrEmpty($regroot)) {
						$regroot = ($regroot -Split 'Value\=')[1]
						$vsname = ($vsname -Split 'Value\=')[1]
					}
					else {
						Write-Message -Level Warning -Message "Can't find instance $vsname on $env:COMPUTERNAME"
						return
					}
				}
				
				if ([System.String]::IsNullOrEmpty($vsname)) { $vsname = $instance }
				
				Write-Message -Level Verbose -Message "Regroot: $regroot"
				Write-Message -Level Verbose -Message "ServiceAcct: $serviceaccount"
				Write-Message -Level Verbose -Message "InstanceName: $instancename"
				Write-Message -Level Verbose -Message "VSNAME: $vsname"
				
				$scriptblock = {
					$regpath = "Registry::HKEY_LOCAL_MACHINE\$($args[0])\MSSQLServer\SuperSocketNetLib"
					$cert = (Get-ItemProperty -Path $regpath -Name Certificate).Certificate
					$forceencryption = (Get-ItemProperty -Path $regpath -Name ForceEncryption).ForceEncryption
					
					[pscustomobject]@{
						ComputerName = $env:COMPUTERNAME
						InstanceName = $args[2]
						SqlInstance = $args[1]
						ForceEncryption = ($forceencryption -eq $true)
						CertificateThumbprint = $cert
					}
				}
				
				try {
					Invoke-Command2 -ComputerName $resolved.fqdn -Credential $Credential -ArgumentList $regroot, $vsname, $instancename -ScriptBlock $scriptblock -ErrorAction Stop
				}
				catch {
					Stop-Function -Message $_ -ErrorRecord $_ -Target $Computer -Continue
				}
			}
		}
	}
}
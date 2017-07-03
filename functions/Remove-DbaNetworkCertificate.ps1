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
		[DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$Credential,
		[switch]$Silent
	)
	process {
		foreach ($instance in $sqlinstance) {
			
			Test-RunAsAdmin -ComputerName $instance.ComputerName
			
			Write-Message -Level Output -Message "Resolving hostname"
			$resolved = Resolve-DbaNetworkName -ComputerName $instance -Turbo
			
			if ($null -eq $resolved) {
				Write-Message -Level Warning -Message "Can't resolve $instance"
				return
			}
			
			Write-Message -Level Output -Message "Connecting to SQL WMI on $($instance.ComputerName)"
			try {
				$sqlwmi = Invoke-ManagedComputerCommand -Server $instance.ComputerName -ScriptBlock { $wmi.Services } -Credential $Credential -ErrorAction Stop | Where-Object DisplayName -eq "SQL Server ($($instance.instancename))"
			}
			catch {
				Stop-Function -Message $_ -Target $sqlwmi
				return
			}
			
			$regroot = ($sqlwmi.AdvancedProperties | Where-Object Name -eq REGROOT).Value
			$vsname = ($sqlwmi.AdvancedProperties | Where-Object Name -eq VSNAME).Value
			$instancename = $instance.instancename # $sqlwmi.DisplayName.Replace('SQL Server (', '').Replace(')', '') # Don't clown, I don't know regex :(
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
			
			if ([System.String]::IsNullOrEmpty($vsname)) { $vsname = $instance.ComputerName }
			
			Write-Message -Level Output -Message "Regroot: $regroot"
			Write-Message -Level Output -Message "ServiceAcct: $serviceaccount"
			Write-Message -Level Output -Message "InstanceName: $instancename"
			Write-Message -Level Output -Message "VSNAME: $vsname"
			
			$scriptblock = {
				$regroot = $args[0]
				$serviceaccount = $args[1]
				$instancename = $args[2]
				$vsname = $args[3]
				
				$regpath = "Registry::HKEY_LOCAL_MACHINE\$($args[0])\MSSQLServer\SuperSocketNetLib"
				$cert = (Get-ItemProperty -Path $regpath -Name Certificate).Certificate
				Set-ItemProperty -Path $regpath -Name Certificate -Value $null
				
				[pscustomobject]@{
					ComputerName = $env:COMPUTERNAME
					InstanceName = $instancename
					SqlInstance = $vsname
					ServiceAccount = $serviceaccount
					RemovedThumbprint = $cert.Thumbprint
				}
			}
			
			if ($PScmdlet.ShouldProcess("local", "Connecting to $ComputerName to remove the cert")) {
				try {
					Invoke-Command2 -ComputerName $resolved.fqdn -Credential $Credential -ArgumentList $regroot, $serviceaccount, $instancename, $vsname -ScriptBlock $scriptblock -ErrorAction Stop
				}
				catch {
					Stop-Function -Message $_ -ErrorRecord $_ -Target $ComputerName -Continue
				}
			}
		}
	}
}
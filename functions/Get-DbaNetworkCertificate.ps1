function Get-DbaNetworkCertificate {
<#
.SYNOPSIS
Simplifies finding computer certificates that are candidates for using with SQL Server's network encryption

.DESCRIPTION
Gets computer certificates on localhost that are candidates for using with SQL Server's network encryption

.PARAMETER ComputerName
The target SQL Server - defaults to localhost. If target is a cluster, you must specify the distinct nodes.

.PARAMETER Credential
Allows you to login to $ComputerName using alternative credentials.

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Certificate

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Get-DbaNetworkCertificate
Gets computer certificates on localhost that are candidates for using with SQL Server's network encryption

.EXAMPLE
Get-DbaNetworkCertificate -ComputerName sql2016

Gets computer certificates on sql2016 that are being used for SQL Server network encryption

#>
	[CmdletBinding()]
	param (
		[parameter(ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer", "SqlInstance")]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[System.Management.Automation.PSCredential]$Credential,
		[switch]$Silent
	)
	
	process {
		foreach ($computer in $computername) {
			
			Write-Message -Level Verbose -Message "Resolving hostname"
			$resolved = Resolve-DbaNetworkName -ComputerName $computer -Turbo
			
			if ($null -eq $resolved) {
				Write-Message -Level Warning -Message "Can't resolve $computer"
				return
			}
			
			Write-Message -Level Verbose -Message "Connecting to SQL WMI on $($SqlInstance.ComputerName)"
			try {
				$instances = Invoke-ManagedComputerCommand -Server $resolved.FQDN -ScriptBlock { $wmi.Services } -Credential $Credential -ErrorAction Stop | Where-Object DisplayName -match "SQL Server \("
			}
			catch {
				Stop-Function -Message $_ -Target $instance
				return
			}
			
			foreach ($instance in $instances) {
				$regroot = ($instance.AdvancedProperties | Where-Object Name -eq REGROOT).Value
				$serviceaccount = $instance.ServiceAccount
				$instancename = $instance.DisplayName.Replace('SQL Server (', '').Replace(')', '') # Don't clown, I don't know regex :(
				
				Write-Message -Level Verbose -Message "Regroot: $regroot"
				Write-Message -Level Verbose -Message "ServiceAcct: $serviceaccount"
				
				if ($null -eq $regroot) {
					Write-Message -Level Warning -Message "Can't find instance $($SqlInstance.InstanceName) on $env:COMPUTERNAME"
					return
				}
				
				$scriptblock = {
					$regroot = $args[0]
					$serviceaccount = $args[1]
					$instancename = $args[2]
					
					$regpath = "Registry::HKEY_LOCAL_MACHINE\$regroot\MSSQLServer\SuperSocketNetLib"
					
					$thumbprint = (Get-ItemProperty -Path $regpath -Name Certificate).Certificate
					
					$cert = Get-ChildItem Cert:\ -Recurse | Where-Object Thumbprint -eq $Thumbprint
					
					if (!$cert) { continue }
					
					[pscustomobject]@{
						ComputerName = $env:COMPUTERNAME
						InstanceName = $instancename
						SqlInstance = "$env:COMPUTERNAME\$instancename"
						ServiceAccount = $serviceaccount
						FriendlyName = $cert.FriendlyName
						DnsNameList = $cert.DnsNameList
						Thumbprint = $cert.Thumbprint
						Generated = $cert.NotBefore
						Expires = $cert.NotAfter
						IssuedTo = $cert.Subject
						IssuedBy = $cert.Issuer
						Certificate = $cert
					} | Select-DefaultView -ExcludeProperty Certificate
				}
				
				if ($PScmdlet.ShouldProcess("local", "Connecting to $ComputerName to import new cert")) {
					try {
						Invoke-Command2 -ComputerName $resolved.fqdn -Credential $Credential -ArgumentList $regroot, $serviceaccount, $instancename -ScriptBlock $scriptblock -ErrorAction Stop
					}
					catch {
						Stop-Function -Message $_ -ErrorRecord $_ -Target $ComputerName -Continue
					}
				}
			}
		}
	}
}
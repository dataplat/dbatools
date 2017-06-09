function Remove-DbaComputerCertificate {
<#
.SYNOPSIS
Removes a computer certificate - useful for removing certs from remote computers

.DESCRIPTION
Removes a computer certificate from a local or remote compuer

.PARAMETER ComputerName
The target SQL Server - defaults to localhost

.PARAMETER Credential
Allows you to login to $ComputerName using alternative credentials

.PARAMETER Store
Certificate store - defaults to LocalMachine

.PARAMETER Folder
Certificate folder - defaults to My (Personal)
	
.PARAMETER Certificate
The target certificate object

.PARAMETER Thumbprint
The thumbprint of the certificate object 

.PARAMETER Path
The path to the target certificate object 

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
Remove-DbaComputerCertificate -ComputerName Server1 -Path C:\temp\cert.cer

Removes the local C:\temp\cer.cer to the remote server Server1 in LocalMachine\My (Personal)

.EXAMPLE
Remove-DbaComputerCertificate -Path C:\temp\cert.cer

Removes the local C:\temp\cer.cer to the local computer's LocalMachine\My (Personal) certificate store

#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
	param (
		[Alias("ServerInstance", "SqlServer", "SqlInstance")]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[System.Management.Automation.PSCredential]$Credential,
		[parameter(ParameterSetName = "Certificate", ValueFromPipeline)]
		[System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
		[string]$Path,
		[string]$Thumbprint,
		[string]$Store = "LocalMachine",
		[string]$Folder = "My",
		[switch]$Silent
	)
	
	process {
		
		if (!$Certificate -and !$Path -and !$Thumbprint) {
			Write-Message -Level Warning -Message "You must specify either Certificate, Path or Thumbprint"
			return
		}
		
		foreach ($computer in $computername) {
			
			$scriptblock = {
				$thumbprint = $args[0]
				$Store = $args[1]
				$Folder = $args[2]
				$Certificate = $args[3]
				$Path = $args[4]
				$Thumbprint = $args[5]
				
				if ($Certificate) {
					$thumbprint = $Certificate.Thumbprint
				}
				
				if ($path) {
					
					if (!(Test-Path -Path $path)) {
						Write-Message -Level Warning -Message "$Path does not exist"
						return
					}
					
					$file = [System.IO.File]::ReadAllBytes($path)
					$Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
					$Certificate.Import($file, $password, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
					$thumbprint = $Certificate.Thumbprint
				}
				
				Write-Verbose "Searching Cert:\$Store\$Folder for thumbprint: $thumbprint"
				$cert = Get-ChildItem "Cert:\$store\$folder" -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
				
				if ($cert) {
					$cert | Remove-Item
					$status = "Removed"
				}
				else {
					$status = "Certificate not found in Cert:\$Store\$Folder"
				}
				
				[pscustomobject]@{
					ComputerName = $computer
					Thumbprint = $thumbprint
					Status = $status
				}
			}
			
			if ($PScmdlet.ShouldProcess("local", "Connecting to $computer to remove cert from Cert:\$Store\$Folder")) {
				try {
					Invoke-Command2 -ComputerName $computer -Credential $Credential -ArgumentList $thumbprint, $store, $folder, $Certificate, $path, $thumbprint -ScriptBlock $scriptblock -ErrorAction Stop
				}
				catch {
					Stop-Function -Message $_ -ErrorRecord $_ -Target $computer -Continue
				}
			}
		}
	}
}
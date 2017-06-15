function Add-DbaComputerCertificate {
<#
.SYNOPSIS
Adds a computer certificate - useful for older systems

.DESCRIPTION
Adds a computer certificate from a local or remote compuer

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

.PARAMETER Path
The local path to the target certificate object
	
.PARAMETER Password
The password for the certificate, if it is password protected

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
Add-DbaComputerCertificate -ComputerName Server1 -Path C:\temp\cert.cer

Adds the local C:\temp\cer.cer to the remote server Server1 in LocalMachine\My (Personal)

.EXAMPLE
Add-DbaComputerCertificate -Path C:\temp\cert.cer

Adds the local C:\temp\cer.cer to the local computer's LocalMachine\My (Personal) certificate store

#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
	param (
		[Alias("ServerInstance", "SqlServer", "SqlInstance")]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[System.Management.Automation.PSCredential]$Credential,
		[securestring]$Password,
		[parameter(ValueFromPipeline)]
		[System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
		[string]$Path,
		[string]$Store = "LocalMachine",
		[string]$Folder = "My",
		[switch]$Silent
	)
	
	begin {
		
		if ($Path) {
			if (!(Test-Path -Path $Path)) {
				Stop-Function -Message "Path ($Path) does not exist."
				return
			}

			try {
				# This may be too much, but ¯\_(ツ)_/¯
				$bytes = [System.IO.File]::ReadAllBytes($path)
				$Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
				$Certificate.Import($bytes, $password, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
			}
			catch {
				Stop-Function -Message "Can't import certificate." -ErrorRecord $_ -Continue
			}
		}
	}
	process {
		if (Test-FunctionInterrupt) { return }
		
		if (!$Certificate -and !$Path) {
			Write-Message -Level Warning -Message "You must specify either Certificate or Path"
			return
		}
		
		if ($Certificate) {
			try {
				$certdata = $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::PFX, $password)
			}
			catch {
				Stop-Function -Message "Can't export certificate" -ErrorRecord $_ -Continue
			}
		}
		
		foreach ($computer in $computername) {
			
			if (![dbavalidate]::IsLocalhost($computer) -and !$Password) {
				$Password = ((65 .. 90) + (97 .. 122) | Get-Random -Count 29 | ForEach-Object { [char]$_ }) -join "" | ConvertTo-SecureString -AsPlainText -Force
			}
			
			$scriptblock = {
				$Store = $args[2]
				$Folder = $args[3]
				
				$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
				$cert.Import($args[0], $args[1], [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
				Write-Verbose "Importing cert to $Folder\$Store"
				$tempstore = New-Object System.Security.Cryptography.X509Certificates.X509Store($Folder, $Store)
				$tempstore.Open('ReadWrite')
				$tempstore.Add($cert)
				$tempstore.Close()
				
				Write-Verbose "Searching Cert:\$Store\$Folder"
				Get-ChildItem "Cert:\$store\$folder" -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
			}
			
			if ($PScmdlet.ShouldProcess("local", "Connecting to $computer to import cert")) {
				try {
					Invoke-Command2 -ComputerName $computer -Credential $Credential -ArgumentList $certdata, $Password, $store, $folder -ScriptBlock $scriptblock -ErrorAction Stop |
					Select-DefaultView -Property FriendlyName, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer
				}
				catch {
					Stop-Function -Message $_ -ErrorRecord $_ -Target $computer -Continue
				}
			}
		}
	}
}
function Add-DbaComputerCertificate {
<#
.SYNOPSIS
Adds a computer certificate useful for Forcing Encryption

.DESCRIPTION
Adds a computer certificate - signed by an Active Directory CA, using the Web Server certificate. Self-signing is not currenty supported but feel free to add it.
	
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

.PARAMETER Store
Certificate store - defaults to LocalMachine

.PARAMETER Folder
Certificate folder - defaults to My (Personal)

.PARAMETER Password
Password to encrypt/decrypt private key for export to remote machine

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
Add-DbaComputerCertificate
Creates a computer certificate signed by the local domain CA for the local machine with the keylength of 1024.

.EXAMPLE
Add-DbaComputerCertificate -ComputerName Server1

Creates a computer certificate signed by the local domain CA _on the local machine_ for server1 with the keylength of 1024. 
	
The certificate is then copied to the new machine over WinRM and imported.

.EXAMPLE
Add-DbaComputerCertificate -ComputerName sqla, sqlb -InstanceClusterName sqlcluster -KeyLength 4096

Creates a computer certificate for sqlcluster, signed by the local domain CA, with the keylength of 4096. 
	
The certificate is then copied to sqla _and_ sqlb over WinRM and imported.

.EXAMPLE
Add-DbaComputerCertificate -ComputerName Server1 -WhatIf

Shows what would happen if the command were run

#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
	param (
		[Alias("ServerInstance", "SqlServer", "SqlInstance")]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[System.Management.Automation.PSCredential]$Credential,
		[securestring]$Password,
		[parameter(ParameterSetName = "Certificate", ValueFromPipeline)]
		[System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
		[string]$Path,
		[string]$Store = "LocalMachine",
		[string]$Folder = "My",
		[switch]$Silent
	)
	
	process {
		
		if (!$Certificate -and !$Path) {
			Write-Message -Level Warning -Message "You must specify either Certificate or Path"
			return
		}
		
		foreach ($computer in $computername) {
			if (![dbavalidate]::IsLocalhost($computer) -and !$Password) {
				Write-Message -Level Output -Message "You have specified a remote computer. A password is required for private key encryption/decryption for import."
				$Password = Read-Host -AsSecureString -Prompt "Password"
			}
			
			if ($Certificate) {
				$tempdir = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
				$tempfile = "$tempdir\cert.cer"
				$certdata = $certificate.Export("pfx", $password)
				[System.IO.File]::WriteAllBytes($tempfile, $certdata)
				$file = [System.IO.File]::ReadAllBytes($tempfile)
				Remove-Item $tempfile
			}
			
			if ($path) {
				$file = [System.IO.File]::ReadAllBytes($path)
				$Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
				$Certificate.Import($file, $password, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
			}
			
			if (![dbavalidate]::IsLocalhost($computer)) {
				if ($PScmdlet.ShouldProcess("local", "Generating pfx and reading from disk")) {
					Write-Message -Level Output -Message "Exporting PFX with password to $temppfx"
					$certdata = $certificate.Export("pfx", $password)
					[System.IO.File]::WriteAllBytes($temppfx, $certdata)
					$file = [System.IO.File]::ReadAllBytes($temppfx)
				}
			}
			
			$scriptblock = {
				$tempdir = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
				$tempfile = "$tempdir\cert.cer"
				$Store = $args[2]
				$Folder = $args[3]
				
				[System.IO.File]::WriteAllBytes($tempfile, $args[0])
				
				$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
				$cert.Import($tempfile, $args[1], [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
				
				$tempstore = New-Object System.Security.Cryptography.X509Certificates.X509Store($Folder, $Store)
				$tempstore.Open('ReadWrite')
				$tempstore.Add($cert)
				$tempstore.Close()
				
				Get-ChildItem "Cert:\$store\$folder" -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
				
				Remove-Item -Path $tempfile
			}
			
			if ($PScmdlet.ShouldProcess("local", "Connecting to $computer to import cert")) {
				try {
					Invoke-Command2 -ComputerName $computer -Credential $Credential -ArgumentList $file, $Password, $store, $folder -ScriptBlock $scriptblock -ErrorAction Stop
				}
				catch {
					Stop-Function -Message $_ -ErrorRecord $_ -Target $computer -Continue
				}
			}
		}
		Remove-Variable -Name Password
	}
}
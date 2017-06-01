function New-DbaComputerCertificate {
<#
.SYNOPSIS
Creates a new computer certificate useful for Forcing Encryption

.DESCRIPTION
Creates a new computer certificate - signed by an Active Directory CA, using the Web Server certificate. Self-signing is not currenty supported but feel free to add it.
	
By default, a key with a length of 4096 and a friendly name of the machines FQDN is generated.
	
This command was originally intended to help automate the process so that SSL certificates can be available for enforcing encryption on connections.

https://blogs.msdn.microsoft.com/sqlserverfaq/2016/09/26/creating-and-registering-ssl-certificates/

The certificate is generated on the client machine and pushed to the remote machine. If your organization's security policies block these kind of certs, 
simply run New-DbaComputerCertificate on the target machine instead of using the -ComputerName parameter.

.PARAMETER ComputerName
The target SQL Server - defaults to localhost

.PARAMETER Credential
Allows you to login to $ComputerName using alternative credentials.

.PARAMETER CaServer
Optional - the CA Server where the request will be sent to

.PARAMETER CaName
The properly formatted CA name of the corresponding CaServer

.PARAMETER Password
Password to encrypt/decrypt private key for export to remote machine
	
.PARAMETER FriendlyName
The FriendlyName listed in the certificate. This defaults to the FQDN of the $ComputerName
	
.PARAMETER KeyLength
The length of the key - defaults to 4096
		
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
New-DbaCertificate
Creates a computer certificate for the local machine with the keylength of 4096.

.EXAMPLE
New-DbaCertificate -ComputerName Server1

Creates a computer certificate _on the local machine_ for server1 with the keylength of 4096. 
	
The certificate is then copied to the new machine over WinRM and imported.

.EXAMPLE
New-DbaCertificate -ComputerName Server1 -WhatIf

Shows what would happen if the command were run

#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
	param (
		[parameter(ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer", "SqlInstance")]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[System.Management.Automation.PSCredential]$Credential,
		[string]$CaServer,
		[string]$CaName,
		[securestring]$Password,
		[string]$FriendlyName = "SQL Server",
		[int]$KeyLength = 4096,
		[switch]$Silent
	)
	begin {
		
		Test-RunAsAdmin
		
		if (!$CaServer -or !$CaName) {
			try {
				Write-Message -Level Output -Message "No CaServer or CaName specified. Finding it."
				# hat tip Vadims Podans
				$domain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
				$domain = "DC=" + $domain -replace '\.', ", DC="
				$pks = [ADSI]"LDAP://CN=Enrollment Services, CN=Public Key Services, CN=Services, CN=Configuration, $domain"
				$cas = $pks.psBase.Children
				
				$allcas = @()
				foreach ($ca in $cas) {
					$allcas += [pscustomobject]@{
						CA = $ca | ForEach-Object { $_.Name }
						Computer = $ca | ForEach-Object { $_.DNSHostName }
					}
				}
			}
			catch {
				Stop-Function -Message "Cannot access Active Directory or find the Certificate Authority: $_"
				return
			}
		}
		
		if (!$CaServer) {
			$CaServer = ($allcas | Select-Object -First 1).Computer
			Write-Message -Level Output -Message "Root Server: $CaServer"
		}
		
		if (!$CaName) {
			$CaName = ($allcas | Select-Object -First 1).CA
			Write-Message -Level Output -Message "Root CA name: $CaName"
		}
		
		$tempdir = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
		$certTemplate = "CertificateTemplate:Computer"
		
	}
	
	process {
		
		if (Test-FunctionInterrupt) { return }
		
		foreach ($computer in $computername) {
			
			if (![dbavalidate]::IsLocalhost($computer) -and !$Password) {
				Write-Message -Level Output -Message "You have specified a remote computer. A password is required for private key encryption/decryption for import."
				$Password = Read-Host -AsSecureString -Prompt "Password"
			}
			
			$dns = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Turbo -WarningAction SilentlyContinue
			
			if (!$dns) {
				$fqdn = "$ComputerName.$env:USERDNSDOMAIN"
				Write-Message -Level Warning -Message "Server name cannot be resolved. Guessing it's $fqdn"
			}
			else {
				$fqdn = $dns.fqdn
			}
			
			Write-Message -Level Output -Message "Processing $computer"
			
			if (!$FriendlyName) {
				$FriendlyName = $fqdn
			}
			
			$certdir = "$tempdir\$fqdn"
			$certinf = "$certdir\request.inf"
			$certcsr = "$certdir\$fqdn.csr"
			$certcrt = "$certdir\$fqdn.cer"
			$certpfx = "$certdir\$fqdn.pfx"
			$temppfx = "$certdir\temp-$fqdn.pfx"
			
			if (Test-Path($certdir)) {
				Write-Message -Level Output -Message "Deleting files from $certdir"
				$null = Remove-Item "$certdir\*.*"
			}
			else {
				Write-Message -Level Output -Message "Creating $certdir"
				$null = mkdir $certdir
			}
			
			Set-Content $certinf "[Version]"
			Add-Content $certinf 'Signature="$Windows NT$"'
			Add-Content $certinf "[NewRequest]"
			Add-Content $certinf "Subject = ""CN=$fqdn"""
			Add-Content $certinf "KeySpec = 1"
			Add-Content $certinf "KeyLength = $KeyLength"
			Add-Content $certinf "Exportable = TRUE"
			Add-Content $certinf "MachineKeySet = TRUE"
			Add-Content $certinf "FriendlyName=""$FriendlyName"""
			Add-Content $certinf "SMIME = False"
			Add-Content $certinf "PrivateKeyArchive = FALSE"
			Add-Content $certinf "UserProtected = FALSE"
			Add-Content $certinf "UseExistingKeySet = FALSE"
			Add-Content $certinf "ProviderName = ""Microsoft RSA SChannel Cryptographic Provider"""
			Add-Content $certinf "ProviderType = 12"
			Add-Content $certinf "RequestType = Cert" #PKCS10
			Add-Content $certinf "Hashalgorithm = sha512"
			Add-Content $certinf "ProviderType = 12"
			Add-Content $certinf "ValidityPeriod = Years"
			Add-Content $certinf "ValidityPeriodUnits = 10"
			Add-Content $certinf "KeyUsage = 0xa0"
			Add-Content $certinf "[EnhancedKeyUsageExtension]"
			Add-Content $certinf "OID=1.3.6.1.5.5.7.3.1"
			Add-Content $certinf "[RequestAttributes]"
			Add-Content $certinf "CertificateTemplate=Machine"
			Add-Content $certinf "SAN=""DNS=$fqdn&DNS=$computer"""
						
			if ($PScmdlet.ShouldProcess("local", "Creating certificate request for $computer")) {
				Write-Message -Level Output -Message "Running: certreq -new $certinf $certcsr"
				$create = certreq -new $certinf $certcsr
			}
			
			if ($PScmdlet.ShouldProcess("local", "Submitting certificate request for $computer to $CaServer\$CaName")) {
				Write-Message -Level Output -Message "certreq -submit -config `"$CaServer\$CaName`" -attrib $certTemplate $certcsr $certcrt $certpfx"
				#$submit = certreq -submit -config ""$CaServer\$CaName"" -attrib $certTemplate $certcsr $certcrt $certpfx
				certreq -submit -config ""$CaServer\$CaName"" -attrib $certcsr $certcrt $certpfx
			}
			
			return
			if ($submit -match "ssued") {
				Write-Message -Level Output -Message "certreq -accept -machine $certcrt"
				$null = certreq -accept -machine $certcrt
				$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
				$cert.Import($certcrt, $null, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
				$storedcert = Get-ChildItem Cert:\LocalMachine\My -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
				
				if ([dbavalidate]::IsLocalhost($computer)) {
					$storedcert
				}
			}
			elseif ($submit) {
				Write-Message -Level Warning -Message "Something went wrong"
				Write-Message -Level Warning -Message "$create"
				Write-Message -Level Warning -Message "$submit"
				Stop-Function -Message "Failure when attempting to create the cert on $computer. Exception: $_" -ErrorRecord $_ -Target $computer -Continue
			}
			
			if (![dbavalidate]::IsLocalhost($computer)) {
				 								
				if ($PScmdlet.ShouldProcess("local", "Removing cert from disk")) {
					$storedcert | Remove-Item
				}
				
				if ($PScmdlet.ShouldProcess("local", "Generating pfx and reading from disk")) {
					Write-Message -Level Output -Message "Exporting PFX with password to $temppfx"
					$certdata = $storedcert.Export("pfx", $password)
					[System.IO.File]::WriteAllBytes($temppfx, $certdata)
					$file = [System.IO.File]::ReadAllBytes($temppfx)
				}
				
				$scriptblock = {
					$tempdir = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
					$filename = "$tempdir\cert.cer"
					
					[System.IO.File]::WriteAllBytes($filename, $args[0])
					$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
					$cert.Import($filename, $args[1], [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
					
					$store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
					$store.Open('ReadWrite')
					$store.Add($cert)
					$store.Close()
					
					Get-ChildItem Cert:\LocalMachine\My -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
					
					Remove-Item -Path $filename
				}
				
				if ($PScmdlet.ShouldProcess("local", "Connecting to $computer to import new cert")) {
					try {
						Invoke-Command2 -ComputerName $computer -Credential $Credential -ArgumentList $file, $Password -ScriptBlock $scriptblock
						Remove-Variable -Name Password
					}
					catch {
						Stop-Function -Message "Failure when attempting to import the cert on $computer. Exception: $_" -InnerErrorRecord $_ -Target $computer -Continue
					}
				}
			}
			if ($PScmdlet.ShouldProcess("local", "Removing all files from $certdir")) {
				Remove-Item -Force -Recurse $certdir -ErrorAction SilentlyContinue
			}
		}
	}
}
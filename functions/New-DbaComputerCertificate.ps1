function New-DbaComputerCertificate {
<#
.SYNOPSIS
Creates a new computer certificate useful for Forcing Encryption

.DESCRIPTION
Creates a new computer certificate - signed by an Active Directory CA, using the Web Server certificate. Self-signing is not currenty supported but feel free to add it.
	
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

.PARAMETER CaServer
Optional - the CA Server where the request will be sent to

.PARAMETER CaName
The properly formatted CA name of the corresponding CaServer

.PARAMETER Password
Password to encrypt/decrypt private key for export to remote machine
	
.PARAMETER FriendlyName
The FriendlyName listed in the certificate. This defaults to the FQDN of the $ComputerName
	
.PARAMETER KeyLength
The length of the key - defaults to 1024
	
.PARAMETER CertificateTemplate
The domain's Certificate Template - WebServer by default.

.PARAMETER InstanceClusterName
When creating certs for a cluster, use this parameter to create the certificate for the cluster node name. Use ComputerName for each of the nodes.
		
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
New-DbaComputerCertificate
Creates a computer certificate signed by the local domain CA for the local machine with the keylength of 1024.

.EXAMPLE
New-DbaComputerCertificate -ComputerName Server1

Creates a computer certificate signed by the local domain CA _on the local machine_ for server1 with the keylength of 1024. 
	
The certificate is then copied to the new machine over WinRM and imported.

.EXAMPLE
New-DbaComputerCertificate -ComputerName sqla, sqlb -InstanceClusterName sqlcluster -KeyLength 4096

Creates a computer certificate for sqlcluster, signed by the local domain CA, with the keylength of 4096. 
	
The certificate is then copied to sqla _and_ sqlb over WinRM and imported.

.EXAMPLE
New-DbaComputerCertificate -ComputerName Server1 -WhatIf

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
		[string]$InstanceClusterName,
		[securestring]$Password,
		[string]$FriendlyName = "SQL Server",
		[string]$CertificateTemplate = "WebServer",
		[int]$KeyLength = 1024,
		[switch]$Silent
	)
	begin {
		Test-RunAsAdmin
		
		function GetHexLength([int]$strLen) {
			$hex = [String]::Format("{0:X2}", $strLen)
			
			if ($strLen -gt 127) { [String]::Format("{0:X2}", 128 + ($hex.Length / 2)) + $hex }
			else { $hex }
		}
		
		function Get-SanExt ([string[]]$hostname) {
			# thanks to Lincoln of 
			# https://social.technet.microsoft.com/Forums/windows/en-US/f568edfa-7f93-46a4-aab9-a06151592dd9/converting-ascii-to-asn1-der
			
			$temp = ''
			foreach ($fqdn in $hostname) {
				# convert each character of fqdn to hex
				$hexString = ($fqdn.ToCharArray() | ForEach-Object{ [String]::Format("{0:X2}", [int]$_) }) -join ''
				
				# length of hex fqdn, in hex
				$hexLength = GetHexLength ($hexString.Length / 2)
				
				# concatenate special code 82, hex length, hex string
				$temp += "82${hexLength}${hexString}"
			}
			# calculate total length of concatenated string, in hex
			$totalHexLength = GetHexLength ($temp.Length / 2)
			# concatenate special code 30, hex length, hex string
			$temp = "30${totalHexLength}${temp}"
			# convert to binary
			$bytes = $(
				for ($i = 0; $i -lt $temp.length; $i += 2) {
					[byte]"0x$($temp.SubString($i, 2))"
				}
			)
			# convert to base 64
			$base64 = [Convert]::ToBase64String($bytes)
			# output in proper format
			for ($i = 0; $i -lt $base64.Length; $i += 64) {
				$line = $base64.Substring($i, [Math]::Min(64, $base64.Length - $i))
				if ($i -eq 0) { "2.5.29.17=$line" }
				else { "_continue_=$line" }
			}
		}
	
	
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
		$certTemplate = "CertificateTemplate:$CertificateTemplate"
		
	}
	
	process {
		
		if (Test-FunctionInterrupt) { return }
		
		foreach ($computer in $computername) {
			if (!$secondarynode) {
				if (![dbavalidate]::IsLocalhost($computer) -and !$Password) {
					Write-Message -Level Output -Message "You have specified a remote computer. A password is required for private key encryption/decryption for import."
					$Password = Read-Host -AsSecureString -Prompt "Password"
				}
				
				if ($InstanceClusterName) {
					if ($InstanceClusterName -notmatch "\.") {
						$fqdn = "$InstanceClusterName.$($env:USERDNSDOMAIN.ToLower())"
					}
					else {
						$fqdn = $InstanceClusterName
					}
				}
				else {
					$dns = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Turbo -WarningAction SilentlyContinue
					
					if (!$dns) {
						$fqdn = "$ComputerName.$env:USERDNSDOMAIN"
						Write-Message -Level Warning -Message "Server name cannot be resolved. Guessing it's $fqdn"
					}
					else {
						$fqdn = $dns.fqdn
					}
				}
				
				if (!$FriendlyName) {
					$FriendlyName = $fqdn
				}
				
				$certdir = "$tempdir\$fqdn"
				$certcfg = "$certdir\request.inf"
				$certcsr = "$certdir\$fqdn.csr"
				$certcrt = "$certdir\$fqdn.crt"
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
				
				# Make sure output is compat with clusters
				$shortname = $fqdn.Split(".")[0]
				
				$san = Get-SanExt $computer, $fqdn
				# Write config file
				Set-Content $certcfg "[Version]"
				Add-Content $certcfg 'Signature="$Windows NT$"'
				Add-Content $certcfg "[NewRequest]"
				Add-Content $certcfg "Subject = ""CN=$fqdn"""
				Add-Content $certcfg "KeySpec = 1"
				Add-Content $certcfg "KeyLength = $KeyLength"
				Add-Content $certcfg "Exportable = TRUE"
				Add-Content $certcfg "MachineKeySet = TRUE"
				Add-Content $certcfg "FriendlyName=""$FriendlyName"""
				Add-Content $certcfg "SMIME = False"
				Add-Content $certcfg "PrivateKeyArchive = FALSE"
				Add-Content $certcfg "UserProtected = FALSE"
				Add-Content $certcfg "UseExistingKeySet = FALSE"
				Add-Content $certcfg "ProviderName = ""Microsoft RSA SChannel Cryptographic Provider"""
				Add-Content $certcfg "ProviderType = 12"
				Add-Content $certcfg "RequestType = PKCS10"
				Add-Content $certcfg "KeyUsage = 0xa0"
				Add-Content $certcfg "[EnhancedKeyUsageExtension]"
				Add-Content $certcfg "OID=1.3.6.1.5.5.7.3.1"
				Add-Content $certcfg "[Extensions]"
				Add-Content $certcfg $san
				Add-Content $certcfg "Critical=2.5.29.17"
				
				if ($PScmdlet.ShouldProcess("local", "Creating certificate request for $computer")) {
					Write-Message -Level Output -Message "Running: certreq -new $certcfg $certcsr"
					$create = certreq -new $certcfg $certcsr
				}
				
				if ($PScmdlet.ShouldProcess("local", "Submitting certificate request for $computer to $CaServer\$CaName")) {
					Write-Message -Level Output -Message "certreq -submit -config `"$CaServer\$CaName`" -attrib $certTemplate $certcsr $certcrt $certpfx"
					$submit = certreq -submit -config ""$CaServer\$CaName"" -attrib $certTemplate $certcsr $certcrt $certpfx
				}
				
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
			}
			
			if (![dbavalidate]::IsLocalhost($computer)) {
				
				if (!$secondarynode) {
					if ($PScmdlet.ShouldProcess("local", "Removing cert from disk")) {
						$storedcert | Remove-Item
					}
					
					if ($PScmdlet.ShouldProcess("local", "Generating pfx and reading from disk")) {
						Write-Message -Level Output -Message "Exporting PFX with password to $temppfx"
						$certdata = $storedcert.Export("pfx", $password)
						[System.IO.File]::WriteAllBytes($temppfx, $certdata)
						$file = [System.IO.File]::ReadAllBytes($temppfx)
					}
					if ($InstanceClusterName) { $secondarynode = $true }
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
						Invoke-Command2 -ComputerName $computer -Credential $Credential -ArgumentList $file, $Password -ScriptBlock $scriptblock -ErrorAction Stop
					}
					catch {
						Stop-Function -Message $_ -ErrorRecord $_ -Target $computer -Continue
					}
				}
			}
			if ($PScmdlet.ShouldProcess("local", "Removing all files from $certdir")) {
				Remove-Item -Force -Recurse $certdir -ErrorAction SilentlyContinue
			}
		}
		Remove-Variable -Name Password
	}
}
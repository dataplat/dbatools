function New-DbaComputerCertificate {
<#
	.SYNOPSIS
		Creates a new computer certificate useful for Forcing Encryption
	
	.DESCRIPTION
		Creates a new computer certificate - self-signed or signed by an Active Directory CA, using the Web Server certificate.
		
		By default, a key with a length of 1024 and a friendly name of the machines FQDN is generated.
		
		This command was originally intended to help automate the process so that SSL certificates can be available for enforcing encryption on connections.
		
		It makes a lot of assumptions - namely, that your account is allowed to auto-enroll and that you have permission to do everything it needs to do ;)
		
		References:
		http://sqlmag.com/sql-server/7-steps-ssl-encryption
		https://azurebi.jppp.org/2016/01/23/using-lets-encrypt-certificates-for-secure-sql-server-connections/
		https://blogs.msdn.microsoft.com/sqlserverfaq/2016/09/26/creating-and-registering-ssl-certificates/
		
		The certificate is generated using AD's webserver SSL template on the client machine and pushed to the remote machine.
	
	.PARAMETER ComputerName
		The target SQL Server - defaults to localhost. If target is a cluster, you must also specify ClusterInstanceName (see below)
	
	.PARAMETER Credential
		Allows you to login to $ComputerName using alternative credentials.
	
	.PARAMETER CaServer
		Optional - the CA Server where the request will be sent to
	
	.PARAMETER CaName
		The properly formatted CA name of the corresponding CaServer
	
	.PARAMETER ClusterInstanceName
		When creating certs for a cluster, use this parameter to create the certificate for the cluster node name. Use ComputerName for each of the nodes.
	
	.PARAMETER Password
		Password to encrypt/decrypt private key for export to remote machine
	
	.PARAMETER FriendlyName
		The FriendlyName listed in the certificate. This defaults to the FQDN of the $ComputerName
	
	.PARAMETER CertificateTemplate
		The domain's Certificate Template - WebServer by default.
	
	.PARAMETER KeyLength
		The length of the key - defaults to 1024
	
	.PARAMETER Store
		Certificate store - defaults to LocalMachine
	
	.PARAMETER Folder
		Certificate folder - defaults to My (Personal)
	
	.PARAMETER Dns
		Specify the Dns entries listed in SAN. By default, it will be ComputerName + FQDN, or in the case of clusters, clustername + cluster FQDN.
	
	.PARAMETER SelfSigned
		Creates a self-signed certificate. All other parameters can still apply except CaServer and CaName because the command does not go and get the certificate signed.
	
	.PARAMETER Silent
		Use this switch to disable any kind of verbose messages
	
	.PARAMETER WhatIf
		Shows what would happen if the command were to run. No actions are actually performed.
	
	.PARAMETER Confirm
		Prompts you for confirmation before executing any changing operations within the command.
	
	.EXAMPLE
		New-DbaComputerCertificate
		Creates a computer certificate signed by the local domain CA for the local machine with the keylength of 1024.
	
	.EXAMPLE
		New-DbaComputerCertificate -ComputerName Server1
		
		Creates a computer certificate signed by the local domain CA _on the local machine_ for server1 with the keylength of 1024.
		
		The certificate is then copied to the new machine over WinRM and imported.
	
	.EXAMPLE
		New-DbaComputerCertificate -ComputerName sqla, sqlb -ClusterInstanceName sqlcluster -KeyLength 4096
		
		Creates a computer certificate for sqlcluster, signed by the local domain CA, with the keylength of 4096.
		
		The certificate is then copied to sqla _and_ sqlb over WinRM and imported.
	
	.EXAMPLE
		New-DbaComputerCertificate -ComputerName Server1 -WhatIf
		
		Shows what would happen if the command were run
	
	.EXAMPLE
		New-DbaComputerCertificate -SelfSigned
		
		Creates a self-signed certificate
	
	.NOTES
		Tags: Certificate
		
		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
	param (
		[parameter(ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer", "SqlInstance")]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[PSCredential]$Credential,
		[string]$CaServer,
		[string]$CaName,
		[string]$ClusterInstanceName,
		[securestring]$Password,
		[string]$FriendlyName = "SQL Server",
		[string]$CertificateTemplate = "WebServer",
		[int]$KeyLength = 1024,
		[string]$Store = "LocalMachine",
		[string]$Folder = "My",
		[string[]]$Dns,
		[switch]$SelfSigned,
		[switch]$Silent
	)
	begin {
		$englishCodes = 9, 1033, 2057, 3081, 4105, 5129, 6153, 7177, 8201, 9225
		if ($englishCodes -notcontains (Get-DbaCmObject Win32_OperatingSystem).OSLanguage) {
			Stop-Function -Message "Currently, this command is only supported in English OS locales. OS Locale detected: $([System.Globalization.CultureInfo]::GetCultureInfo([int](Get-DbaCmObject Win32_OperatingSystem).OSLanguage).DisplayName)`nWe apologize for the inconvenience and look into providing universal language support in future releases."
			return
		}
		
		if (-not (Test-ElevationRequirement -ComputerName $env:COMPUTERNAME)) { return }
		
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
		
		if ((!$CaServer -or !$CaName) -and !$SelfSigned) {
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
				Stop-Function -Message "Cannot access Active Directory or find the Certificate Authority: $_" -ErrorRecord $_
				return
			}
			
			if (!$CaServer) {
				$CaServer = ($allcas | Select-Object -First 1).Computer
				Write-Message -Level Output -Message "Root Server: $CaServer"
			}
			
			if (!$CaName) {
				$CaName = ($allcas | Select-Object -First 1).CA
				Write-Message -Level Output -Message "Root CA name: $CaName"
			}
		}
		
		$tempdir = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
		$certTemplate = "CertificateTemplate:$CertificateTemplate"
	}
	
	process {
		if (Test-FunctionInterrupt) { return }
		
		foreach ($computer in $computername) {
			
			if (!$secondarynode) {
				if (!$Computer.IsLocalhost -and !$Password) {
					$Password = ((65 .. 90) + (97 .. 122) | Get-Random -Count 29 | ForEach-Object { [char]$_ }) -join "" | ConvertTo-SecureString -AsPlainText -Force
				}
				
				if ($ClusterInstanceName) {
					if ($ClusterInstanceName -notmatch "\.") {
						$fqdn = "$ClusterInstanceName.$env:USERDNSDOMAIN"
					}
					else {
						$fqdn = $ClusterInstanceName
					}
				}
				else {
					$resolved = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -WarningAction SilentlyContinue
					
					if (!$resolved) {
						$fqdn = "$ComputerName.$env:USERDNSDOMAIN"
						Write-Message -Level Warning -Message "Server name cannot be resolved. Guessing it's $fqdn"
					}
					else {
						$fqdn = $resolved.fqdn
					}
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
				
				if (!$dns) {
					$dns = $shortname, $fqdn
				}
				
				$san = Get-SanExt $dns
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
				if ($SelfSigned) {
					Add-Content $certcfg "RequestType = Cert"
				}
				else {
					Add-Content $certcfg "RequestType = PKCS10"
				}
				Add-Content $certcfg "KeyUsage = 0xa0"
				Add-Content $certcfg "[EnhancedKeyUsageExtension]"
				Add-Content $certcfg "OID=1.3.6.1.5.5.7.3.1"
				Add-Content $certcfg "[Extensions]"
				Add-Content $certcfg $san
				Add-Content $certcfg "Critical=2.5.29.17"
				
				
				if ($PScmdlet.ShouldProcess("local", "Creating certificate for $computer")) {
					Write-Message -Level Output -Message "Running: certreq -new $certcfg $certcsr"
					$create = certreq -new $certcfg $certcsr
				}
				
				if ($SelfSigned) {
					$serial = (($create -Split "Serial Number:" -Split "Subject")[2]).Trim() # D:
					$storedcert = Get-ChildItem Cert:\LocalMachine\My -Recurse | Where-Object SerialNumber -eq $serial
					
					if ($computer.IsLocalhost) {
						$storedcert | Select-Object * | Select-DefaultView -Property FriendlyName, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer
					}
				}
				else {
					if ($PScmdlet.ShouldProcess("local", "Submitting certificate request for $computer to $CaServer\$CaName")) {
						Write-Message -Level Output -Message "certreq -submit -config `"$CaServer\$CaName`" -attrib $certTemplate $certcsr $certcrt $certpfx"
						$submit = certreq -submit -config ""$CaServer\$CaName"" -attrib $certTemplate $certcsr $certcrt $certpfx
					}
					
					if ($submit -match "ssued") {
						Write-Message -Level Output -Message "certreq -accept -machine $certcrt"
						$null = certreq -accept -machine $certcrt
						$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
						$cert.Import($certcrt, $null, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
						$storedcert = Get-ChildItem "Cert:\$store\$folder" -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
					}
					elseif ($submit) {
						Write-Message -Level Warning -Message "Something went wrong"
						Write-Message -Level Warning -Message "$create"
						Write-Message -Level Warning -Message "$submit"
						Stop-Function -Message "Failure when attempting to create the cert on $computer. Exception: $_" -ErrorRecord $_ -Target $computer -Continue
					}
					
					if ($Computer.IsLocalhost) {
						$storedcert | Select-Object * | Select-DefaultView -Property FriendlyName, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer
					}
				}
			}
			
			if (!$Computer.IsLocalhost) {
				
				if (!$secondarynode) {
					if ($PScmdlet.ShouldProcess("local", "Generating pfx and reading from disk")) {
						Write-Message -Level Output -Message "Exporting PFX with password to $temppfx"
						$certdata = $storedcert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::PFX, $password)
					}
					
					if ($PScmdlet.ShouldProcess("local", "Removing cert from disk but keeping it in memory")) {
						$storedcert | Remove-Item
					}
					
					if ($ClusterInstanceName) { $secondarynode = $true }
				}
				
				$scriptblock = {
					$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
					$cert.Import($args[0], $args[1], "Exportable,PersistKeySet")
					
					$certstore = New-Object System.Security.Cryptography.X509Certificates.X509Store($args[3], $args[2])
					$certstore.Open('ReadWrite')
					$certstore.Add($cert)
					$certstore.Close()
					Get-ChildItem "Cert:\$($args[2])\$($args[3])" -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
				}
				
				if ($PScmdlet.ShouldProcess("local", "Connecting to $computer to import new cert")) {
					try {
						Write-Message -Level Output -Message "Connecting to $computer"
						Invoke-Command2 -ComputerName $computer -Credential $Credential -ArgumentList $certdata, $Password, $Store, $Folder -ScriptBlock $scriptblock -ErrorAction Stop |
						Select-DefaultView -Property DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer
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
	}
}
function New-DbaComputerCertificate {
<#
.SYNOPSIS
Creates a new computer certificate

.DESCRIPTION
Creates a new computer certificate. If no computer is specified, the certificate will be created in master.

https://blogs.msdn.microsoft.com/sqlserverfaq/2016/09/26/creating-and-registering-ssl-certificates/
	
.PARAMETER ComputerName
The SQL Server to create the certificates on.

.PARAMETER Credential
Allows you to login to SQL Server using alternative credentials.

.PARAMETER computer
The computer where the certificate will be created. Defaults to master.

.PARAMETER Name
Optional secure string used to create the certificate.

.PARAMETER Subject
Optional secure string used to create the certificate.
	
.PARAMETER StartDate
Optional secure string used to create the certificate.
	
.PARAMETER ExpirationDate
Optional secure string used to create the certificate.
	
.PARAMETER ActiveForServiceBrokerDialog
Optional secure string used to create the certificate.

.PARAMETER Password
Optional password - if no password is supplied, the password will be protected by the master key
	
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
New-DbaCertificate -ComputerName Server1

You will be prompted to securely enter your password, then a certificate will be created in the master computer on server1 if it does not exist.

.EXAMPLE
New-DbaCertificate -ComputerName Server1 -computer db1 -Confirm:$false

Suppresses all prompts to install but prompts to securely enter your password and creates a certificate in the 'db1' computer
#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
	param (
		[parameter(ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer", "SqlInstance")]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[System.Management.Automation.PSCredential]$Credential,
		[string]$RootServer,
		[string]$RootCaName,
		[string]$FriendlyName,
		[int]$KeyLength = 4096,
		[switch]$Silent
	)
	begin {
		
		if (!$RootServer -or !$RootCaName) {
			try {
				Write-Message -Level Verbose -Message "No RootServer or RootCaName specified. Finding it."
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
				Stop-Function -Message "Cannot access Active Direcotry or find the Certificate Authority: $_"
				return
			}
		}
		
		if (!$RootServer) {
			$RootServer = ($allcas | Select-Object -First 1).Computer
			Write-Message -Level Verbose -Message "Root Server: $RootServer"
		}
		
		if (!$RootCaName) {
			$RootCaName = ($allcas | Select-Object -First 1).CA
			Write-Message -Level Verbose -Message "Root CA name: $RootCaName"
		}
		
		$tempdir = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
		$certTemplate = "CertificateTemplate:WebServer"
	}
	
	process {
		
		if (Test-FunctionInterrupt) { return }
		
		foreach ($computer in $computername) {
			Test-RunAsAdmin -ComputerName $computer
			
			$dns = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Turbo -WarningAction SilentlyContinue
			
			if (!$dns) {
				$fqdn = "$ComputerName.$env:USERDNSDOMAIN"
				Write-Message -Level Warning -Message "Server name cannot be resolved. Guessing it's $fqdn"
			}
			else {
				$fqdn = $dns.fqdn
			}
			
			Write-Message -Level Verbose -Message "Processing $computer"
			
			if (!$FriendlyName) {
				$FriendlyName = $fqdn
			}
			
			$certdir = "$tempdir\$fqdn"
			$certcfg = "$certdir\request.inf"
			$certcsr = "$certdir\$fqdn.csr"
			$certcrt = "$certdir\$fqdn.crt"
			$certpfx = "$certdir\$fqdn.pfx"
			
			if (Test-Path($certdir)) {
				Write-Message -Level Verbose -Message "Deleting files from $certdir"
				$null = Remove-Item "$certdir\*.*"
			}
			else {
				Write-Message -Level Verbose -Message "Creating $certdir"
				$null = mkdir $certdir
			}
			
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
			Add-Content $certcfg "OID=1.3.6.1.5.5.7.3.1 ; this is for Server Authentication"
			Add-Content $certcfg "[RequestAttributes]"
			Add-Content $certcfg "SAN=""DNS=$fqdn&DNS=$computer"""
			
			Write-Message -Level Verbose -Message "Running: certreq -new $certcfg $certcsr"
			$create = certreq -new $certcfg $certcsr
			
			Write-Message -Level Verbose -Message "certreq -submit -config `"$RootServer\$RootCaName`" -attrib $certTemplate $certcsr $certcrt $certpfx"
			$submit = certreq -submit -config ""$RootServer\$RootCaName"" -attrib $certTemplate $certcsr $certcrt $certpfx
			
			if ($submit -match "ssued") {
				Write-Message -Level Verbose -Message "certreq -accept -machine $certcrt"
				$null = certreq -accept -machine $certcrt
				$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
				$cert.Import($certcrt, $null, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
				$storedcert = Get-ChildItem Cert:\LocalMachine\My -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
				
				if ([dbavalidate]::IsLocalhost($computer)) {
					$storedcert
				}
			}
			else {
				Write-Message -Level Warning -Message "Something went wrong"
				Write-Message -Level Warning -Message "$create"
				Write-Message -Level Warning -Message "$submit"
			}
			
			if (1 -eq 2 -and $allcas) {
				Write-Message -Level Verbose -Message "Trying next CA"
				$RootServer = ($allcas | Select-Object -Last 1).Computer
				$RootCaName = ($allcas | Select-Object -Last 1).Name
				
				Write-Message -Level Verbose -Message "certreq -submit -config `"$RootServer\$RootCaName`" -attrib $certTemplate $certcsr $certcrt $certpfx"
				certreq -submit -config ""$RootServer\$RootCaName"" -attrib $certTemplate $certcsr $certcrt $certpfx
				
				Write-Message -Level Verbose -Message "certreq -accept -machine $certcrt"
				certreq -accept -machine $certcrt
			}
			
			if (![dbavalidate]::IsLocalhost($computer)) {
				$storedcert | Remove-Item
				
				$file = [System.IO.File]::ReadAllBytes($certcrt)
				
				$scriptblock = {
					$tempdir = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
					$filename = "$tempdir\cert.cer"
					[System.IO.File]::WriteAllBytes($filename, $args)
					certutil -addstore -f -enterprise Personal "$filename"
					#-Enterprise 
					$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
					$cert.Import($filename, $null, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
					$cert 
					Get-ChildItem Cert:\LocalMachine -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
					
					Remove-Item -Path $filename
				}
				
				Invoke-Command2 -ComputerName $computer -Credential $Credential -ArgumentList $file -ScriptBlock $scriptblock
			}
			Remove-Item -Force -Recurse $certdir -ErrorAction SilentlyContinue
		}
	}
}
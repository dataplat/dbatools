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

.PARAMETER RootServer
The computer where the certificate will be created. Defaults to master.

.PARAMETER RootCaName
Optional secure string used to create the certificate.

.PARAMETER FriendlyName
Optional secure string used to create the certificate.
	
.PARAMETER KeyLength
Optional secure string used to create the certificate.
		
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
Creates


.EXAMPLE
New-DbaCertificate -ComputerName Server1 -Confirm:$false


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
				Write-Message -Level Output -Message "No RootServer or RootCaName specified. Finding it."
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
			Write-Message -Level Output -Message "Root Server: $RootServer"
		}
		
		if (!$RootCaName) {
			$RootCaName = ($allcas | Select-Object -First 1).CA
			Write-Message -Level Output -Message "Root CA name: $RootCaName"
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
			
			Write-Message -Level Output -Message "Processing $computer"
			
			if (!$FriendlyName) {
				$FriendlyName = $fqdn
			}
			
			$certdir = "$tempdir\$fqdn"
			$certcfg = "$certdir\request.inf"
			$certcsr = "$certdir\$fqdn.csr"
			$certcrt = "$certdir\$fqdn.crt"
			$certpfx = "$certdir\$fqdn.pfx"
			
			if (Test-Path($certdir)) {
				Write-Message -Level Output -Message "Deleting files from $certdir"
				$null = Remove-Item "$certdir\*.*"
			}
			else {
				Write-Message -Level Output -Message "Creating $certdir"
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
			
			if ($PScmdlet.ShouldProcess($baseaddress, "Creating certificate request for $computer")) {
				Write-Message -Level Output -Message "Running: certreq -new $certcfg $certcsr"
				$create = certreq -new $certcfg $certcsr
			}
			
			if ($PScmdlet.ShouldProcess($baseaddress, "Submitting certificate request for $computer to $RootServer\$RootCaName")) {
				Write-Message -Level Output -Message "certreq -submit -config `"$RootServer\$RootCaName`" -attrib $certTemplate $certcsr $certcrt $certpfx"
				$submit = certreq -submit -config ""$RootServer\$RootCaName"" -attrib $certTemplate $certcsr $certcrt $certpfx
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
			}
			
			if (![dbavalidate]::IsLocalhost($computer)) {
				
				if ($PScmdlet.ShouldProcess($baseaddress, "Removing cert from disk")) {
					$storedcert | Remove-Item
				}
				
				if ($PScmdlet.ShouldProcess($baseaddress, "Reading newly generated cert")) {
					$file = [System.IO.File]::ReadAllBytes($certcrt)
				}
				
				$scriptblock = {
					$tempdir = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
					$filename = "$tempdir\cert.cer"
					
					[System.IO.File]::WriteAllBytes($filename, $args)
					$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
					$cert.Import($filename, $null, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
					
					$store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
					$store.Open('ReadWrite')
					$store.Add($cert)
					$store.Close()
					
					Get-ChildItem Cert:\LocalMachine\My -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
					
					Remove-Item -Path $filename
				}
				
				if ($PScmdlet.ShouldProcess($baseaddress, "Connecting to $computer to import new cert")) {
					Invoke-Command2 -ComputerName $computer -Credential $Credential -ArgumentList $file -ScriptBlock $scriptblock
				}
			}
			Remove-Item -Force -Recurse $certdir -ErrorAction SilentlyContinue
		}
	}
}
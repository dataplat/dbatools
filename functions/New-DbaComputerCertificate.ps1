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
		[string]$Org = "IT",
		[string]$City = "Brussels",
		[string]$State = "BE",
		[string]$Country = "BE",
		[string]$OrganizationalUnit = "IT",
		[string]$FriendlyName,
		[int]$KeyLength = 4096,
		[switch]$Silent
	)
	process {
		foreach ($computer in $computername) {

			Test-RunAsAdmin -ComputerName $computer.ComputerName
			
			if (!$RootServer -or !$RootCaName) {
				try {
					Write-Verbose "No RootServer or RootCaName specified. Finding it."
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
					Write-Warning "Cannot access Active Direcotry or find the Certificate Authority: $_"
					return
				}
			}
			
			if (!$RootServer) {
				$RootServer = ($allcas | Select-Object -First 1).Computer
				Write-Verbose "Root Server: $RootServer"
			}
			
			if (!$RootCaName) {
				$RootCaName = ($allcas | Select-Object -First 1).CA
				Write-Verbose "Root CA name: $RootCaName"
			}
			
			$scriptblock = {
				$computer = $env:COMPUTERNAME
				Write-Verbose "Processing $computer"
				
				$fqdn = ("$env:computername.$env:userdnsdomain").ToLower()
				
				if (!$FriendlyName) {
					$FriendlyName = $fqdn
				}
				
				# Place the certs on a network location if your farm is larger than one server
				$tempdir = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
				
				$fqdn = ("$env:computername.$env:userdnsdomain").ToLower()
				$certTemplate = "CertificateTemplate:WebServer"
				
				$certdir = "$tempdir\$fqdn"
				$certcfg = "$certdir\request.inf"
				$certcsr = "$certdir\$fqdn.csr"
				$certcrt = "$certdir\$fqdn.crt"
				$certpfx = "$certdir\$fqdn.pfx"
				
				if (Test-Path($certdir)) {
					Write-Verbose "Deleting files from $certdir"
					$null = Remove-Item "$certdir\*.*"
				}
				else {
					Write-Verbose "Creating $certdir"
					$null = mkdir $certdir
				}
				Write-Warning $certdir
				
				Set-Content $certcfg "[Version]"
				Add-Content $certcfg 'Signature="$Windows NT$"'
				Add-Content $certcfg "[NewRequest]"
				Add-Content $certcfg "Subject = ""CN=$fqdn, OU=$OrganizationalUnit, O=$org, L=$city, S=$state, C=$country"""
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
				Add-Content $certcfg "SAN=""DNS=$fqdn&DNS=$env:computername"""
				
				Write-Verbose "Running: certreq -new $certcfg $certcsr"
				$create = cmd /c certreq -new $certcfg $certcsr
				
				Write-Verbose "certreq -submit -config `"$RootServer\$RootCaName`" -attrib $certTemplate $certcsr $certcrt $certpfx"
				$submit = cmd /c certreq -submit -config ""$RootServer\$RootCaName"" -attrib $certTemplate $certcsr $certcrt $certpfx
				
				if ($submit -match "ssued") {
					Write-Verbose "certreq -accept -machine $certcrt"
					$null = cmd /c certreq -accept -machine $certcrt
					$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
					$cert.Import($certcrt, $null, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
					
					Get-ChildItem Cert:\LocalMachine\My -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
					
				}
				else {
					Write-Warning "Something went wrong"
					Write-Warning "$create"
					Write-Warning "$submit"
				}
				
				if (1 -eq 2 -and $allcas) {
					Write-Verbose "Trying next CA"
					$RootServer = ($allcas | Select-Object -Last 1).Computer
					$RootCaName = ($allcas | Select-Object -Last 1).Name
					
					Write-Verbose "certreq -submit -config `"$RootServer\$RootCaName`" -attrib $certTemplate $certcsr $certcrt $certpfx"
					cmd /c certreq -submit -config ""$RootServer\$RootCaName"" -attrib $certTemplate $certcsr $certcrt $certpfx
					
					Write-Verbose "certreq -accept -machine $certcrt"
					cmd /c certreq -accept -machine $certcrt
				}
				
				Remove-Item -Force -Recurse $certdir -ErrorAction SilentlyContinue
			}
			
			Invoke-Command2 -ComputerName $computer.ComputerName -ScriptBlock $scriptblock -Verbose:$verbose -ArgumentList $PSBoundParameters
		}
	}
}
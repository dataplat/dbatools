function New-DbaComputerCertificate {
<#
.SYNOPSIS
Creates a new computer certificate

.DESCRIPTION
Creates a new computer certificate. If no computer is specified, the certificate will be created in master.

https://blogs.msdn.microsoft.com/sqlserverfaq/2016/09/26/creating-and-registering-ssl-certificates/
	
.PARAMETER SqlInstance
The SQL Server to create the certificates on.

.PARAMETER SqlCredential
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
New-DbaCertificate -SqlInstance Server1

You will be prompted to securely enter your password, then a certificate will be created in the master computer on server1 if it does not exist.

.EXAMPLE
New-DbaCertificate -SqlInstance Server1 -computer db1 -Confirm:$false

Suppresses all prompts to install but prompts to securely enter your password and creates a certificate in the 'db1' computer
#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
	param (
		[parameter(Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$ComputerName,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[parameter(Mandatory)]
		[string[]]$Name,
		[string[]]$Subject = $Name,
		[datetime]$StartDate = (Get-Date),
		[datetime]$ExpirationDate = $StartDate.AddYears(5),
		[string]$RootServer,
		[string]$RootCaName,
		[string]$Email = "admin@corp.com",
		[string]$Org = "Corp",
		[string]$City = "NYC",
		[string]$State = "NY",
		[string]$Country = "US",
		[string]$OrganizationalUnit = "IT",
		[string]$FriendlyName,
		[string]$ValidityPeriod = "Years",
		[int]$ValidityPeriodUnits = 10,
		[int]$KeyLength = 4096,
		[switch]$Silent
	)
	process {
		foreach ($computer in $computername) {
			
			$computer = $computer.ComputerName
			
			if (!$RootServer -or !$RootCaName) {
				try {
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
					Stop-Function -Message "Cannot access Active Direcotry or find the Certificate Authority" -ErrorRecord $_
					return
				}
			}
			
			if (!$RootServer) {
				$RootServer = $cas.Computer
			}
			
			if (!$RootCaName) {
				$RootServer = $cas.Name
			}
			
			$thisfqdn = ("$env:computername.$env:userdnsdomain").ToLower()
			
			if (!$Friendlyname) {
				$Friendlyname = $thisfqdn
			}
			
			$time = (Get-Date -uformat "%m%d%Y%H%M%S")
			$certTemplate = "CertificateTemplate:Computer"
			
			$tempdir = $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("")
			$filename = "$thisfqdn-$time"
			$server = $thisfqdn.Substring(0, $thisfqdn.IndexOf("."))
			
			$filenamedir = "$tempdir\$filename"
			$inf = "$filenamedir\request.inf"
			$csr = "$filenamedir\$filename.csr"
			$crt = "$filenamedir\$filename.crt"
			$pfx = "$filenamedir\$filename.pfx"
			
			if (Test-Path($filenamedir)) { $null = Remove-Item "$filenamedir\*.*" }
			else { $null = mkdir $filenamedir }
			
			Set-Content $inf "[Version]"
			Add-Content $inf 'Signature="$Windows NT$"'
			Add-Content $inf "[NewRequest]"
			Add-Content $inf "Subject = ""CN=$thisfqdn, OU=$OrganizationalUnit, O=$org, L=$city, S=$state, C=$country"""
			Add-Content $inf "KeySpec = 1"
			Add-Content $inf "KeyLength = $KeyLength"
			Add-Content $inf "Exportable = TRUE"
			Add-Content $inf "MachineKeySet = TRUE"
			Add-Content $inf "FriendlyName=""$friendlyname"""
			Add-Content $inf "SMIME = False"
			Add-Content $inf "PrivateKeyArchive = FALSE"
			Add-Content $inf "UserProtected = FALSE"
			Add-Content $inf "UseExistingKeySet = FALSE"
			Add-Content $inf "ProviderName = ""Microsoft RSA SChannel Cryptographic Provider"""
			Add-Content $inf "ProviderType = 12"
			Add-Content $inf "RequestType = Cert" #PKCS10
			Add-Content $inf "Hashalgorithm = sha512"
			Add-Content $inf "KeyUsage = 0xA0"
			Add-Content $inf "ValidityPeriod = $ValidityPeriod"
			Add-Content $inf "ValidityPeriodUnits = $ValidityPeriodUnits"
			
			Add-Content $inf "[EnhancedKeyUsageExtension]"
			Add-Content $inf "OID=1.3.6.1.5.5.7.3.1" # this is for Server Authentication"
			Add-Content $inf "[RequestAttributes]"
			Add-Content $inf "SAN=""DNS=$thisfqdn&DNS=$server"""
			
			certreq -new $inf $csr
			certreq -submit -config ""$RootServer\$RootCaName"" -attrib $certTemplate $csr $crt $pfx
			certreq -accept -machine $crt
		}
	}
}
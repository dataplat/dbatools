Function Export-DbaCertificate {
<#
.SYNOPSIS
 Exports certificates from SQL Server using smo

.DESCRIPTION
Exports certificates from SQL Server using smo and outputs the .cer and .pvk files

.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER Path
The Path to output the files to. The path is relative to the SQL Server itself. If no path is specified, the default data directory will be used

.PARAMETER Database
Exports the encryptor for specific database(s).

.PARAMETER Certificate
Exports certificate that matches the name(s).

.PARAMETER Suffix
The suffix of the filename of the exported certificate

.PARAMETER EncryptionPassword 
A string value that specifies the system path to encrypt the private key.

.PARAMETER DecryptionPassword 
A string value that specifies the system path to decrypt the private key.

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.PARAMETER CertificateCollection 
Internal parameter to support pipeline input

.NOTES
Original Author: Jess Pomfret (@jpomfret)
Tags: Migration, Certificate

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Get-DbaCertificate -SqlInstance sql2016 | Export-DbaCertificate
Exports all certificates found on sql2016 to the default data directory. Prompts for encryption and decrecyption passwords.

.EXAMPLE
Export-DbaCertificate -SqlInstance Server1 -Path \\Server1\Certificates -EncryptionPassword (ConvertTo-SecureString -force -AsPlainText GoodPass1234!!)
Exports all the certificates on the specified SQL Server

.EXAMPLE
$EncryptionPassword = ConvertTo-SecureString -AsPlainText "GoodPass1234!!" -force
Export-DbaCertificate -SqlInstance Server1 -Path \\Server1\Certificates -EncryptionPassword $EncryptionPassword -Database Database1
Exports the certificate that is used as the encryptor for a specific database on the specified SQL Server

.EXAMPLE
Export-DbaCertificate -SqlInstance Server1 -Path \\Server1\Certificates -Certificate CertTDE
Exports all certificates named CertTDE on the specified SQL Server, not specifying the -EncryptionPassword will generate a prompt for user entry.

#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory, ParameterSetName = "instance")]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[parameter(ParameterSetName = "instance")]
		[object[]]$Certificate,
		[parameter(ParameterSetName = "instance")]
		[object[]]$Database,
		[parameter(Mandatory = $false)]
		[Security.SecureString]$EncryptionPassword = (Read-Host "EncryptionPassword (recommended, not required)" -AsSecureString),
		[parameter(Mandatory = $false)]
		[Security.SecureString]$DecryptionPassword = (Read-Host "DecryptionPassword (required if encryption password is specified)" -AsSecureString),
		[System.IO.FileInfo]$Path,
		[string]$Suffix = "$(Get-Date -format 'yyyyMMddHHmmssms')",
		[parameter(ValueFromPipeline, ParameterSetName = "collection")]
		[Microsoft.SqlServer.Management.Smo.Certificate[]]$CertificateCollection,
		[switch]$Silent
	)
	
	begin {
		
		if ($EncryptionPassword.Length -eq 0 -and $DecryptionPassword.Length -gt 0) {
			Stop-Function -Message "If you specify an dencryption password, you must also specify an encryption password" -Target $DecryptionPassword
		}
		
		function export-cert ($cert) {
			$certname = $cert.Name
			$database = $cert.Parent
			$server = $database.Parent
			$instance = $server.Name
			$actualpath = $Path
			
			if ($null -eq $actualpath) {
				$actualpath = Get-SqlDefaultPaths -SqlInstance $server -filetype Data
			}
			
			$fullcertname = "$actualpath\$certname$Suffix"
			$exportpathkey = "$fullcertname.pvk"
			
			if (!(Test-DbaSqlPath -SqlInstance $server -Path $actualpath)) {
				Stop-Function -Message "$SqlInstance cannot access $actualpath" -Target $actualpath
			}
			
			if ($Pscmdlet.ShouldProcess($instance, "Exporting certificate $certname from $database on $instance to $actualpath")) {
				Write-Message -Level Verbose -Message "Exporting Certificate: $certname to $fullcertname"
				try {
										
					$exportpathcert = "$fullcertname.cer"
					
					# because the password shouldn't go to memory...
					if ($EncryptionPassword.Length -gt 0 -and $DecryptionPassword.Length -gt 0) {
						
						Write-Message -Level Verbose -Message "Both passwords passed in. Will export both cer and pvk."
						
						$cert.export(
							$exportpathcert,
							$exportpathkey,
							[System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($EncryptionPassword)),
							[System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($DecryptionPassword))
						)
					}
					elseif ($EncryptionPassword.Length -gt 0 -and $DecryptionPassword.Length -eq 0) {
						Write-Message -Level Verbose -Message "Only encryption password passed in. Will export both cer and pvk."
						
						$cert.export(
							$exportpathcert,
							$exportpathkey,
							[System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($EncryptionPassword))
						)
					}
					else {
						Write-Message -Level Verbose -Message "No passwords passed in. Will export just cer."
						$exportpathkey = "Password required to export key"
						$cert.export($exportpathcert)
					}
					
					[pscustomobject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.DomainInstanceName
						Database = $database.name
						Certificate = $certname
						ExportPathCert = $exportpathcert
						ExportPathKey = $exportpathkey
						Status = "Success"
					}
				}
				catch {
					
					if ($_.Exception.InnerException) {
						$exception = $_.Exception.InnerException.ToString() -Split "System.Data.SqlClient.SqlException: "
						$exception = ($exception[1] -Split "at Microsoft.SqlServer.Management.Common.ConnectionManager")[0]
					}
					else {
						$exception = $_.Exception
					}
						[pscustomobject]@{
							ComputerName = $server.NetName
							InstanceName = $server.ServiceName
							SqlInstance = $server.DomainInstanceName
							Database = $database.name
							Certificate = $certname
							ExportPathCert = $exportpathcert
							ExportPathKey = $exportpathkey
							Status = "Failure: $exception"
						}
					Stop-Function -Message "$certname from $database on $instance cannot be exported." -Continue -Target $cert -InnerErrorRecord $_
				}
			}
		}
	}
	
	process {
		if (Test-FunctionInterrupt) { return }
		foreach ($instance in $sqlinstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failed to connect to: $instance" -Target $instance -InnerErrorRecord $_
				return
			}
			
			$CertificateCollection = Get-DbaCertificate -SqlInstance $server -Certificate $Certificate -Database $database
			$CertificateCollection = $CertificateCollection | where Name -NotLike "##*"
			if (!$CertificateCollection) {
				Write-Message -Level Output -Message "No certificates found to export."
				continue
			}
			
		}
		
		foreach ($cert in $CertificateCollection) {
			if ($cert.Name.StartsWith("##")) {
				Write-Message -Level Output -Message "Skipping system cert $cert"
			}
			else {
				export-cert $cert
			}
		}
	}
}
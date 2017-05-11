Function Export-DbaCertificate {
<#
.SYNOPSIS
 Exports certificates from SQL Server using smo

.DESCRIPTION
Exports certificates from SQL Server using smo and outputs the .cer and .pvk files along with a .sql file to create the certificate.

.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER Path
The Path to output the files to.

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
Export-DbaCertificate -SqlInstance Server1 -Path \\Server1\Certificates -EncryptionPassword (ConvertTo-SecureString -force -AsPlainText GoodPass1234!!)
Exports all the certificates on the specified SQL Server

.EXAMPLE
$EncryptionPassword = ConvertTo-SecureString -AsPlainText "GoodPass1234!!" -force
Export-DbaCertificate -SqlInstance Server1 -Path \\Server1\Certificates -EncryptionPassword $EncryptionPassword -Databases Database1
Exports the certificate that is used as the encryptor for a specific database on the specified SQL Server

.EXAMPLE
Export-DbaCertificate -SqlInstance Server1 -Path \\Server1\Certificates -Certificate CertTDE
Exports the certificate named CertTDE on the specified SQL Server, not specifying the -EncryptionPassword will generate a prompt for user entry.

.EXAMPLE
Export-DbaCertificate -SqlInstance Server1 -Path \\Server1\Certificates -EncryptionPassword (ConvertTo-SecureString -force -AsPlainText GoodPass1234!!) -NoOutFile
Exports all the certificates on the specified SQL Server to the path but does not generate a .sql file for CREATE CERTIFICATE statments.


#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory, ParameterSetName = "instance")]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[parameter(ParameterSetName = "instance")]
		[object[]]$Certificate,
		[parameter(ParameterSetName = "instance")]
		[object[]]$Database,
		[parameter(Mandatory = $false)]
		[Security.SecureString]$EncryptionPassword = (Read-Host "EncryptionPassword (not required)" -AsSecureString),
		[parameter(Mandatory = $false)]
		[Security.SecureString]$DecryptionPassword = (Read-Host "DecryptionPassword (not required)" -AsSecureString),
		[System.IO.FileInfo]$Path,
		[string]$Suffix = "$(Get-Date -format 'yyyyMMddHHmmssms')",
		[parameter(ValueFromPipeline, ParameterSetName = "collection")]
		[Microsoft.SqlServer.Management.Smo.Certificate[]]$CertificateCollection,
		[switch]$Silent
	)
	
	begin {
		function export-cert ($cert) {
			$certname = $cert.Name
			$database = $cert.Parent
			$server = $database.Parent
			$instance = $server.Name
			
			if (!$psboundparameters.Path) {
				$Path = Get-SqlDefaultPaths -SqlServer $server -filetype Data
			}
			
			$fullcertname = "$path\$certname$Suffix"
			
			if (!(Test-SqlPath -SqlServer $server -Path $path)) {
				Stop-Function -Message "$SqlInstance cannot access $path" -Continue -Target $path
			}
			
			if ($Pscmdlet.ShouldProcess($instance, "Exporting certificate $certname from $database on $instance to $Path")) {
				Write-Message -Level Verbose -Message "Exporting Certificate: $certname to $fullcertname"
				try {
					# because the password shouldn't go to memory...
					if ($DecryptionPassword) {
						$exportpathkey = "$fullcertname.pvk"
					}
					else {
						$exportpathkey = $null
					}
					
					$exportpathcert = "$fullcertname.cer"
					
					if ($EncryptionPassword.Length -gt 0 -and $DecryptionPassword.Length -gt 0) {
						
						Write-Message -Level Verbose -Message "Both passwords passed in. Will export both cer and pvk."
						
						$cert.export(
							$exportpathcert,
							$exportpathkey,
							[System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($EncryptionPassword)),
							[System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($DecryptionPassword))
						)
					}
					elseif ($EncryptionPassword -and !$DecryptionPassword) {
						$cert.export(
							$exportpathcert,
							[System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($EncryptionPassword))
						)
					}
					elseif (!$EncryptionPassword -and $DecryptionPassword) {
						Write-Message -Level Verbose -Message "Exporting cer with no password, pvk with password."

						$cert.export(
							$exportpathcert,
							$exportpathkey,
							$null,
							[System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($DecryptionPassword))
						)
					}
					else {
						
						Write-Message -Level Verbose -Message "No passwords passed in. Will export just cer."
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
					$exception = $_.Exception.InnerException.ToString() -Split "System.Data.SqlClient.SqlException: "
					$exception = ($exception[1] -Split "at Microsoft.SqlServer.Management.Common.ConnectionManager")[0]
					
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
		foreach ($instance in $sqlinstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failed to connect to: $instance" -Target $instance -InnerErrorRecord $_
				return
			}
			
			$CertificateCollection = Get-DbaCertificate -SqlInstance $server -Certificate $Certificate -Database $database
			
			if (!$certs) {
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
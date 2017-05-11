Function Export-DbaCertificate
{
<#
.SYNOPSIS
 Exports certificates from SQL Server using smo

.DESCRIPTION
Exports certificates from SQL Server using smo and outputs the .cer and .pvk files along with a .sql file to create the certificate.

.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER Path
The Path to output the files to.

.PARAMETER Databases
Exports the encryptor for specific database(s).

.PARAMETER Certificates
Exports certificate that matches the name(s).

.PARAMETER Password
Secure string used to encrypt the exported private key.

.PARAMETER SkipSQLFile
Does not generate a .sql file with the CREATE CERTIFICATE syntax in the path.
Use this to avoid generating script file that contains password.

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.NOTES
Original Author: Jess Pomfret (@jpomfret and/or website)
Tags: Migration, Certificate

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Export-DbaCertificate  -SqlServer Server1 -Path \\Server1\Certificates -password (ConvertTo-SecureString -force -AsPlainText GoodPass1234!!)
Exports all the certificates on the specified SQL Server

.EXAMPLE
$password = ConvertTo-SecureString -AsPlainText "GoodPass1234!!" -force
Export-DbaCertificate  -SqlServer Server1 -Path \\Server1\Certificates -password $password -Databases Database1
Exports the certificate that is used as the encryptor for a specific database on the specified SQL Server

.EXAMPLE
Export-DbaCertificate  -SqlServer Server1 -Path \\Server1\Certificates -Certificate CertTDE
Exports the certificate named CertTDE on the specified SQL Server, not specifying the -Password will generate a prompt for user entry.

.EXAMPLE
Export-DbaCertificate  -SqlServer Server1 -Path \\Server1\Certificates -password (ConvertTo-SecureString -force -AsPlainText GoodPass1234!!) -SkipSQLFile
Exports all the certificates on the specified SQL Server to the path but does not generate a .sql file for CREATE CERTIFICATE statments.


#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[string]$Path,
		[array]$Certificates,
		[Security.SecureString] $Password = (Read-Host "Password" -AsSecureString),
		[switch]$SkipSQLFile = $false,
		[switch]$Silent	
	)

	DynamicParam { 
		if ($sqlserver) { 
		Get-ParamSqlDatabases -SqlServer $sqlserver -SqlCredential $SqlCredential
		} 
	}

	BEGIN {
		$databases = $psboundparameters.Databases
		$server = Connect-SqlServer $SqlServer $SqlCredential
				
		if ($path.Length -eq 0) {
			$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
			$mydocs = [Environment]::GetFolderPath('MyDocuments')
			$path = "$mydocs\$($server.name.replace('\', '$'))-$timenow-sp_configure.sql"
		} elseif ($path.EndsWith('\')) {
			$path = $path.TrimEnd('\')
		}
	
	}
	
	PROCESS {

			if($Databases) {
				$certs = @()
				foreach ($database in $Databases) {
					$certName = $server.Databases[$Database].DatabaseEncryptionKey.EncryptorName
					$certs += $server.Databases['master'].Certificates | where-object {$_.name -eq $certName}
				}
			} elseif($Certificates) {
				$certs = @()
				foreach ($Certificate in $Certificates) {
					$certs += $server.Databases['master'].Certificates | where-object {$_.name -eq $Certificate}
				}
			} else {
				$certs = $server.Databases['master'].Certificates | where-object {$_.name -notlike '##*'}
			}

			if(!$certs) {
				Stop-Function -Message "No certificates found to export." -Continue
			}

			if (!$path.StartsWith('\')) {
				Stop-Function -Message "Path should be a UNC share." -Continue
			}

			Write-Message -Level Verbose -Message "Exporting Certificates"			
			$certSql = @()
			foreach ($cert in $certs) {
				$exportLocation = "$path\$($cert.name)"
				if ($Pscmdlet.ShouldProcess("[$($cert.name)]' on $SqlServer", "Exporting Certificate")) {
					Write-Message -Level Verbose -Message ("Exporting Certificate: {0} to {1}" -f $cert.name, $exportLocation )
					try {
						$cert.export("$exportLocation.cer","$exportLocation.pvk", [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password)))
						
						if(!$SkipSQLFile) {
						$certSql += (
							"CREATE CERTIFICATE [{0}]  
							FROM FILE = '{1}{2}.cer'
							WITH PRIVATE KEY 
							( 
								FILE = '{1}{2}.pvk' ,
								DECRYPTION BY PASSWORD = '{3}'
							)
							GO
							" -f $cert.name, $exportLocation, $c.encryptorName , [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password)))
						}
					} catch {
						Write-Message -Level Warning -Message $_ -ErrorRecord $_ -Target $instance
					}
				}
			}
			if(!$SkipSQLFile) {
				if ($Pscmdlet.ShouldProcess("$path", "Exporting SQL Script")) {
					if($certsql) { 
						try { 
							$certsql | Out-File "$path\CreateCertificates.sql" -ErrorAction Stop
						} catch {
							Write-Message -Level Warning -Message $_ -ErrorRecord $_ -Target $instance
						}
					}
				}
			}
			return $path
	} END {
		$server.ConnectionContext.Disconnect()

	}
}
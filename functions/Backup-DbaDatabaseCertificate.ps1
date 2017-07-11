function Backup-DbaDatabaseCertificate {
	<#
		.SYNOPSIS
			Exports database certificates from SQL Server using SMO.

		.DESCRIPTION
			Exports database certificates from SQL Server using SMO and outputs the .cer and .pvk files.

		.PARAMETER SqlInstance
			SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input to allow the function
			to be executed against multiple SQL Server instances.
		
		.PARAMETER SqlCredential
			SqlCredential object to connect as. If not specified, current Windows login will be used.

		.PARAMETER Certificate
			Exports certificate that matches the name(s).
		
		.PARAMETER Database
			Exports the encryptor for specific database(s).

		.PARAMETER ExcludeDatabase
			Database(s) to skip when exporting encryptors.

		.PARAMETER EncryptionPassword 
			A string value that specifies the system path to encrypt the private key.

		.PARAMETER DecryptionPassword 
			A string value that specifies the system path to decrypt the private key.

		.PARAMETER Path
			The path to output the files to. The path is relative to the SQL Server itself. If no path is specified, the default data directory will be used.
		
		.PARAMETER Suffix
			The suffix of the filename of the exported certificate.

		.PARAMETER CertificateCollection 
			Internal parameter to support pipeline input.

		.PARAMETER Confirm 
			Prompts you for confirmation before executing any changing operations within the command. 

		.PARAMETER Silent 
			Use this switch to disable any kind of verbose messages.

		.PARAMETER WhatIf 
			Shows what would happen if the command were to run. No actions are actually performed. 

		.NOTES
			Original Author: Jess Pomfret (@jpomfret)
			Tags: Migration, Certificate

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.EXAMPLE
			Backup-DbaDatabaseCertificate -SqlInstance Server1
			Exports all the certificates on the specified SQL Server to the default data path for the instance.

		.EXAMPLE
			$cred = Get-Credential sqladmin
			Backup-DbaDatabaseCertificate -SqlInstance Server1 -SqlCredential $cred

			Connects using sqladmin credential and exports all the certificates on the specified SQL Server to the default data path for the instance.

		.EXAMPLE
			Backup-DbaDatabaseCertificate -SqlInstance Server1 -Certificate Certificate1
			Exports only the certificate named Certificate1 on the specified SQL Server to the default data path for the instance.

		.EXAMPLE
			Backup-DbaDatabaseCertificate -SqlInstance Server1 -Database AdventureWorks
			Exports only the certificates for AdventureWorks on the specified SQL Server to the default data path for the instance.

		.EXAMPLE
			Backup-DbaDatabaseCertificate -SqlInstance Server1 -ExcludeDatabase AdventureWorks
			Exports all certificates except those for AdventureWorks on the specified SQL Server to the default data path for the instance.

		.EXAMPLE
			Backup-DbaDatabaseCertificate -SqlInstance Server1 -Path \\Server1\Certificates -EncryptionPassword (ConvertTo-SecureString -force -AsPlainText GoodPass1234!!)
			Exports all the certificates on the specified SQL Server.

		.EXAMPLE
			$EncryptionPassword = ConvertTo-SecureString -AsPlainText "GoodPass1234!!" -force
			$DecryptionPassword = ConvertTo-SecureString -AsPlainText "Password4567!!" -force
			Backup-DbaDatabaseCertificate -SqlInstance Server1 -EncryptionPassword $EncryptionPassword -DecryptionPassword $DecryptionPassword
			Exports all the certificates on the specified SQL Server using the supplied DecryptionPassword, since an EncryptionPassword is specified private keys are also exported.

		.EXAMPLE
			Backup-DbaDatabaseCertificate -SqlInstance Server1 -Path \\Server1\Certificates
			Exports all certificates on the specified SQL Server to the specified path.

		.EXAMPLE
			Backup-DbaDatabaseCertificate -SqlInstance Server1 -Suffix DbaTools
			Exports all certificates on the specified SQL Server to the specified path, appends DbaTools to the end of the filenames.

		.EXAMPLE
			Get-DbaDatabaseCertificate -SqlInstance sql2016 | Backup-DbaDatabaseCertificate
			Exports all certificates found on sql2016 to the default data directory. Prompts for encryption and decryption passwords.
	#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory, ParameterSetName = "instance")]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential,
		[parameter(ParameterSetName = "instance")]
		[object[]]$Certificate,
		[parameter(ParameterSetName = "instance")]
		[object[]]$Database,
		[parameter(ParameterSetName = "instance")]
		[object[]]$ExcludeDatabase,
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
			$certName = $cert.Name
			$db = $cert.Parent
			$server = $db.Parent
			$instance = $server.Name
			$actualPath = $Path
			
			if ($null -eq $actualPath) {
				$actualPath = Get-SqlDefaultPaths -SqlInstance $server -filetype Data
			}
			
			$fullCertName = "$actualPath\$certName$Suffix"
			$exportPathKey = "$fullCertName.pvk"
			
			if (!(Test-DbaSqlPath -SqlInstance $server -Path $actualPath)) {
				Stop-Function -Message "$SqlInstance cannot access $actualPath" -Target $actualPath
			}
			
			if ($Pscmdlet.ShouldProcess($instance, "Exporting certificate $certName from $db on $instance to $actualPath")) {
				Write-Message -Level Verbose -Message "Exporting Certificate: $certName to $fullCertName"
				try {
										
					$exportPathCert = "$fullCertName.cer"
					
					# because the password shouldn't go to memory...
					if ($EncryptionPassword.Length -gt 0 -and $DecryptionPassword.Length -gt 0) {
						
						Write-Message -Level Verbose -Message "Both passwords passed in. Will export both cer and pvk."
						
						$cert.export(
							$exportPathCert,
							$exportPathKey,
							[System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($EncryptionPassword)),
							[System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($DecryptionPassword))
						)
					}
					elseif ($EncryptionPassword.Length -gt 0 -and $DecryptionPassword.Length -eq 0) {
						Write-Message -Level Verbose -Message "Only encryption password passed in. Will export both cer and pvk."
						
						$cert.export(
							$exportPathCert,
							$exportPathKey,
							[System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($EncryptionPassword))
						)
					}
					else {
						Write-Message -Level Verbose -Message "No passwords passed in. Will export just cer."
						$exportPathKey = "Password required to export key"
						$cert.export($exportPathCert)
					}
					
					[pscustomobject]@{
						ComputerName   = $server.NetName
						InstanceName   = $server.ServiceName
						SqlInstance    = $server.DomainInstanceName
						Database       = $db.Name
						Certificate    = $certName
						exportPathCert = $exportPathCert
						exportPathKey  = $exportPathKey
						Status         = "Success"
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
						ComputerName   = $server.NetName
						InstanceName   = $server.ServiceName
						SqlInstance    = $server.DomainInstanceName
						Database       = $db.Name
						Certificate    = $certName
						exportPathCert = $exportPathCert
						exportPathKey  = $exportPathKey
						Status         = "Failure: $exception"
					}
					Stop-Function -Message "$certName from $db on $instance cannot be exported." -Continue -Target $cert -InnerErrorRecord $_
				}
			}
		}
	}
	
	process {
		if (Test-FunctionInterrupt) { return }
		foreach ($instance in $sqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
				return
			}
			$databases = Get-DbaDatabase -SqlInstance $server
			if ($Database) {
				$databases = $databases | Where-Object Name -in $Database
			}
			if ($ExcludeDatabase) {
				$databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
			}
			
			foreach ($db in $databases.Name) {
                $CertificateCollection = Get-DbaDatabaseCertificate -SqlInstance $server -Database $db
                if ($Certificate) {
					$CertificateCollection = $CertificateCollection | Where-Object Name -In $Certificate
				}
				$CertificateCollection = $CertificateCollection | Where-Object Name -NotLike "##*"
				if (!$CertificateCollection) {
					Write-Message -Level Output -Message "No certificates found to export in $db."
					continue
				}
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
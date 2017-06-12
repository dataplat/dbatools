function Copy-DbaCredential {
	<#
		.SYNOPSIS
			Copy-DbaCredential migrates SQL Server Credentials from one SQL Server to another, while maintaining Credential passwords.

		.DESCRIPTION
			By using password decryption techniques provided by Antti Rantasaari (NetSPI, 2014), this script migrates SQL Server Credentials from one server to another, while maintaining username and password.

			Credit: https://blog.netspi.com/decrypting-mssql-database-link-server-passwords/
			License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause

		.PARAMETER Source
			Source SQL Server (2005 and above). You must have sysadmin access to both SQL Server and Windows.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Destination
			Destination SQL Server (2005 and above). You must have sysadmin access to both SQL Server and Windows.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER CredentialIdentity
			Auto-populated list of Credentials from Source. If no Credential is specified, all Credentials will be migrated.
			Note: if spaces exist in the credential name, you will have to type "" or '' around it. I couldn't figure out a way around this.

		.PARAMETER Force
			By default, if a Credential exists on the source and destination, the Credential is not copied over. Specifying -force will drop and recreate the Credential on the Destination server.

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: WSMan, Migration
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires:
				- PowerShell Version 3.0, SQL Server SMO,
				- Administrator access on Windows
				- sysadmin access on SQL Server.
				- DAC access enabled for local (default)
			Limitations: Hasn't been tested thoroughly. Works on Win8.1 and SQL Server 2012 & 2014 so far.

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaCredential

		.EXAMPLE
			Copy-DbaCredential -Source sqlserver2014a -Destination sqlcluster

			Description
			Copies all SQL Server Credentials on sqlserver2014a to sqlcluster. If credentials exist on destination, they will be skipped.

		.EXAMPLE
			Copy-DbaCredential -Source sqlserver2014a -Destination sqlcluster -CredentialIdentity "PowerShell Proxy Account" -Force

			Description
			Copies over one SQL Server Credential (PowerShell Proxy Account) from sqlserver to sqlcluster. If the credential already exists on the destination, it will be dropped and recreated.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Source,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SourceSqlCredential,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$DestinationSqlCredential,
		[object[]]$CredentialIdentity,
		[switch]$Force,
		[switch]$Silent
	)

	begin {
		function Get-SqlCredential {
			<#
				.SYNOPSIS
					Gets Credential Logins

					This function is heavily based on Antti Rantasaari's script at http://goo.gl/omEOrW
					Antti Rantasaari 2014, NetSPI
					License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause

				.OUTPUT
					System.Data.DataTable
			#>
			[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
			param (
				[DbaInstanceParameter]$SqlInstance,
				[System.Management.Automation.PSCredential]$SqlCredential
			)

			$server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
			$sourcename = $server.name

			# Query Service Master Key from the database - remove padding from the key
			# key_id 102 eq service master key, thumbprint 3 means encrypted with machinekey
			$sql = "SELECT substring(crypt_property,9,len(crypt_property)-8) FROM sys.key_encryptions WHERE key_id=102 and (thumbprint=0x03 or thumbprint=0x0300000001)"
			try { $smkbytes = $server.ConnectionContext.ExecuteScalar($sql) }
			catch { throw "Can't execute SQL on $sourcename" }

			$sourcenetbios = Resolve-NetBiosName $server
			$instance = $server.InstanceName
			$serviceInstanceId = $server.serviceInstanceId

			# Get entropy from the registry - hopefully finds the right SQL server instance
			try {
				[byte[]]$entropy = Invoke-Command -ComputerName $sourcenetbios -argumentlist $serviceInstanceId {
					$serviceInstanceId = $args[0]
					$entropy = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$serviceInstanceId\Security\").Entropy
					return $entropy
				}
			}
			catch { throw "Can't access registry keys on $sourcename. Quitting." }

			# Decrypt the service master key
			try {
				$servicekey = Invoke-Command -ComputerName $sourcenetbios -argumentlist $smkbytes, $Entropy {
					Add-Type -assembly System.Security
					Add-Type -assembly System.Core
					$smkbytes = $args[0]; $Entropy = $args[1]
					$servicekey = [System.Security.Cryptography.ProtectedData]::Unprotect($smkbytes, $Entropy, 'LocalMachine')
					return $servicekey
				}
			}
			catch { throw "Can't unprotect registry data on $($source.name)). Quitting." }

			# Choose the encryption algorithm based on the SMK length - 3DES for 2008, AES for 2012
			# Choose IV length based on the algorithm
			if (($servicekey.Length -ne 16) -and ($servicekey.Length -ne 32)) {
				throw "Unknown key size. Cannot continue. Quitting."
			}

			if ($servicekey.Length -eq 16) {
				$decryptor = New-Object System.Security.Cryptography.TripleDESCryptoServiceProvider
				$ivlen = 8
			}
			elseif ($servicekey.Length -eq 32) {
				$decryptor = New-Object System.Security.Cryptography.AESCryptoServiceProvider
				$ivlen = 16
			}

			# Query link server password information from the Db. Remove header from pwdhash, extract IV (as iv) and ciphertext (as pass)
			# Ignore links with blank credentials (integrated auth ?)

			if ($server.IsClustered -eq $false) {
				$connstring = "Server=ADMIN:$sourcenetbios\$instance;Trusted_Connection=True"
			}
			else {
				$dacenabled = $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue


				if ($dacenabled -eq $false) {
					If ($Pscmdlet.ShouldProcess($server.name, "Enabling DAC on clustered instance")) {
						Write-Message -Level Verbose -Message "DAC must be enabled for clusters, even when accessed from active node. Enabling."
						$server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $true
						$server.Configuration.Alter()
					}
				}

				$connstring = "Server=ADMIN:$sourcename;Trusted_Connection=True"
			}


			$sql = "SELECT name,credential_identity,substring(imageval,5,$ivlen) iv, substring(imageval,$($ivlen + 5),len(imageval)-$($ivlen + 4)) pass from sys.credentials cred inner join sys.sysobjvalues obj on cred.credential_id = obj.objid where valclass=28 and valnum=2"

			# Get entropy from the registry
			try {
				$creds = Invoke-Command -ComputerName $sourcenetbios -argumentlist $connstring, $sql {
					$connstring = $args[0]; $sql = $args[1]
					$conn = New-Object System.Data.SqlClient.SQLConnection($connstring)
					try {
						$conn.open()
						$cmd = New-Object System.Data.SqlClient.SqlCommand($sql, $conn);
						$data = $cmd.ExecuteReader()
						$dt = New-Object "System.Data.DataTable"
						$dt.Load($data)
						$conn.Close()
						$conn.Dispose()
						return $dt
					}
					catch {
						Write-Message -Level Warning -Message "Can't establish local DAC connection to $sourcename from $sourcename or other error. Quitting."
					}
				}
			}
			catch {
				Write-Message -Level Warning -Message "Can't establish local DAC connection to $sourcename from $sourcename or other error. Quitting."
			}

			if ($server.IsClustered -and $dacenabled -eq $false) {
				If ($Pscmdlet.ShouldProcess($server.name, "Disabling DAC on clustered instance")) {
					Write-Message -Level Verbose -Message "Setting DAC config back to 0"
					$server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $false
					$server.Configuration.Alter()
				}
			}

			$decryptedlogins = New-Object "System.Data.DataTable"
			[void]$decryptedlogins.Columns.Add("Credential")
			[void]$decryptedlogins.Columns.Add("Identity")
			[void]$decryptedlogins.Columns.Add("Password")

			# Go through each row in results
			foreach ($cred in $creds) {
				# decrypt the password using the service master key and the extracted IV
				$decryptor.Padding = "None"
				$decrypt = $decryptor.Createdecryptor($servicekey, $cred.iv)
				$stream = New-Object System.IO.MemoryStream ( , $cred.pass)
				$crypto = New-Object System.Security.Cryptography.CryptoStream $stream, $decrypt, "Write"

				$crypto.Write($cred.pass, 0, $cred.pass.Length)
				[byte[]]$decrypted = $stream.ToArray()

				# convert decrypted password to unicode
				$encode = New-Object System.Text.UnicodeEncoding

				# Print results - removing the weird padding (8 bytes in the front, some bytes at the end)...
				# Might cause problems but so far seems to work.. may be dependant on SQL server version...
				# If problems arise remove the next three lines..
				$i = 8; foreach ($b in $decrypted) { if ($decrypted[$i] -ne 0 -and $decrypted[$i + 1] -ne 0 -or $i -eq $decrypted.Length) { $i -= 1; break; }; $i += 1; }
				$decrypted = $decrypted[8..$i]

				[void]$decryptedlogins.Rows.Add($($cred.name), $($cred.credential_identity), $($encode.GetString($decrypted)))
			}
			return $decryptedlogins
		}

		function Copy-Credential {
			<#
				.SYNOPSIS
					Copies Credentials from one server to another using a combination of SMO's .Script() and manual password updates.

				.OUTPUT
					System.Data.DataTable
			#>
			param (
				[string[]]$credentials,
				[bool]$force
			)

			Write-Message -Level Verbose -Message "Collecting Credential logins and passwords on $($sourceserver.name)"
			$sourcecredentials = Get-SqlCredential $sourceserver

			if ($CredentialIdenity -ne $null) {
				$credentiallist = $sourceserver.credentials | Where-Object { $CredentialIdentity -contains $_.Name }
			}
			else {
				$credentiallist = $sourceserver.credentials
			}


			Write-Message -Level Verbose -Message "Starting migration"
			foreach ($credential in $credentiallist) {
				$destserver.credentials.Refresh()
				$credentialname = $credential.name

				if ($destserver.credentials[$credentialname] -ne $null) {
					if (!$force) {
						Write-Message -Level Warning -Message "$credentialname exists $($destserver.name). Skipping."
						continue
					}
					else {
						If ($Pscmdlet.ShouldProcess($destination.name, "Dropping $identity")) {
							$destserver.credentials[$credentialname].Drop()
							$destserver.credentials.refresh()
						}
					}
				}

				Write-Message -Level Verbose -Message "Attempting to migrate $credentialname"

				try {
					$currentcred = $sourcecredentials | Where-Object { $_.Credential -eq $credentialname }
					$identity = $currentcred.Identity
					$password = $currentcred.Password

					If ($Pscmdlet.ShouldProcess($destination.name, "Copying $identity")) {
						$sql = "CREATE CREDENTIAL [$credentialname] WITH IDENTITY = N'$identity', SECRET = N'$password'"
						Write-Message -Level Debug -Message $sql
						$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
						$destserver.Credentials.Refresh()
						Write-Message -Level Verbose -Message "$credentialname successfully copied"
					}
				}
				catch {
					Write-Exception $_
				}
			}
		}

		$sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName

		if ($SourceSqlCredential.username -ne $null) {
			Write-Message -Level Warning -Message "You are using SQL credentials and this script requires Windows admin access to the $Source server. Trying anyway."
		}

		if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9) {
			throw "Credentials are only supported in SQL Server 2005 and above. Quitting."
		}

		Invoke-SmoCheck -SqlInstance $sourceserver
		Invoke-SmoCheck -SqlInstance $destserver
	}
	process {
		Write-Message -Level Verbose -Message "Getting NetBios name for $source"
		$sourcenetbios = Resolve-NetBiosName $sourceserver

		Write-Message -Level Verbose -Message "Checking if remote access is enabled on $source"
		winrm id -r:$sourcenetbios 2>$null | Out-Null

		if ($LastExitCode -ne 0) {
			Write-Message -Level Warning -Message "Having trouble with accessing PowerShell remotely on $source. Do you have Windows admin access and is PowerShell Remoting enabled? Anyway, good luck! This may work."
		}

		# This output is wrong. Will fix later.
		Write-Message -Level Verbose -Message "Checking if Remote Registry is enabled on $source"
		try { Invoke-Command -ComputerName $sourcenetbios { Get-ItemProperty -Path "HKLM:\SOFTWARE\" } }
		catch { throw "Can't connect to registry on $source. Quitting." }

		# Magic happens here
		Copy-Credential $credentials -force:$force

	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlCredential
	}
}

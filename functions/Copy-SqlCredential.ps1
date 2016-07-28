Function Copy-SqlCredential
{
<# 
.SYNOPSIS 
Copy-SqlCredential migrates SQL Server Credentials from one SQL Server to another, while maintaining Credential passwords.

.DESCRIPTION 
By using password decryption techniques provided by Antti Rantasaari (NetSPI, 2014), this script migrates SQL Server Credentials from one server to another, while maintaining username and password.

Credit: https://blog.netspi.com/decrypting-mssql-database-link-server-passwords/
License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER Source
Source SQL Server (2005 and above). You must have sysadmin access to both SQL Server and Windows.

.PARAMETER Destination
Destination SQL Server (2005 and above). You must have sysadmin access to both SQL Server and Windows.

.PARAMETER Credentials
Auto-populated list of Credentials from Source. If no Credential is specified, all Credentials will be migrated.
Note: if spaces exist in the credential name, you will have to type "" or '' around it. I couldn't figure out a way around this.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Force
By default, if a Credential exists on the source and destination, the Credential is not copied over. Specifying -force will drop and recreate the Credential on the Destination server.


.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: 	PowerShell Version 3.0, SQL Server SMO, 
			Sys Admin access on Windows and SQL Server. DAC access enabled for local (default)
Limitations: Hasn't been tested thoroughly. Works on Win8.1 and SQL Server 2012 & 2014 so far.		

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlCredential

.EXAMPLE   
Copy-SqlCredential -Source sqlserver2014a -Destination sqlcluster

Description
Copies all SQL Server Credentials on sqlserver2014a to sqlcluster. If credentials exist on destination, they will be skipped.

.EXAMPLE   
Copy-SqlCredential -Source sqlserver2014a -Destination sqlcluster -Credentials "PowerShell Proxy Account" -Force

Description
Copies over one SQL Server Credential (PowerShell Proxy Account) from sqlserver to sqlcluster. If the credential already exists on the destination, it will be dropped and recreated.

#>	
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[switch]$Force
		
	)
	
	DynamicParam { if ($source) { return (Get-ParamSqlCredentials -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	BEGIN
	{
		
		Function Get-SqlCredentials
		{
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
				[object]$SqlServer,
				[System.Management.Automation.PSCredential]$SqlCredential
			)
			
			$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
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
			try
			{
				[byte[]]$entropy = Invoke-Command -ComputerName $sourcenetbios -argumentlist $serviceInstanceId {
					$serviceInstanceId = $args[0]
					$entropy = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$serviceInstanceId\Security\").Entropy
					return $entropy
				}
			}
			catch { throw "Can't access registry keys on $sourcename. Quitting." }
			
			# Decrypt the service master key
			try
			{
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
			if (($servicekey.Length -ne 16) -and ($servicekey.Length -ne 32))
			{
				throw "Unknown key size. Cannot continue. Quitting."
			}
			
			if ($servicekey.Length -eq 16)
			{
				$decryptor = New-Object System.Security.Cryptography.TripleDESCryptoServiceProvider
				$ivlen = 8
			}
			elseif ($servicekey.Length -eq 32)
			{
				$decryptor = New-Object System.Security.Cryptography.AESCryptoServiceProvider
				$ivlen = 16
			}
			
			# Query link server password information from the Db. Remove header from pwdhash, extract IV (as iv) and ciphertext (as pass)
			# Ignore links with blank credentials (integrated auth ?)
			
			if ($server.IsClustered -eq $false)
			{
				$connstring = "Server=ADMIN:$sourcenetbios\$instance;Trusted_Connection=True"
			}
			else
			{
				$dacenabled = $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue
				
				
				if ($dacenabled -eq $false)
				{
					If ($Pscmdlet.ShouldProcess($server.name, "Enabling DAC on clustered instance"))
					{
						Write-Verbose "DAC must be enabled for clusters, even when accessed from active node. Enabling."
						$server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $true
						$server.Configuration.Alter()
					}
				}
				
				$connstring = "Server=ADMIN:$sourcename;Trusted_Connection=True"
			}
			
			
			$sql = "SELECT name,credential_identity,substring(imageval,5,$ivlen) iv, substring(imageval,$($ivlen + 5),len(imageval)-$($ivlen + 4)) pass from sys.credentials cred inner join sys.sysobjvalues obj on cred.credential_id = obj.objid where valclass=28 and valnum=2"
			
			# Get entropy from the registry
			try
			{
				$creds = Invoke-Command -ComputerName $sourcenetbios -argumentlist $connstring, $sql {
					$connstring = $args[0]; $sql = $args[1]
					$conn = New-Object System.Data.SqlClient.SQLConnection($connstring)
					try
					{
						$conn.open()
						$cmd = New-Object System.Data.SqlClient.SqlCommand($sql, $conn);
						$data = $cmd.ExecuteReader()
						$dt = New-Object "System.Data.DataTable"
						$dt.Load($data)
						$conn.Close()
						$conn.Dispose()
						return $dt
					}
					catch 
					{
						Write-Warning "Can't establish local DAC connection to $sourcename from $sourcename or other error. Quitting."
					}
				}
			}
			catch 
			{
				Write-Warning "Can't establish local DAC connection to $sourcename from $sourcename or other error. Quitting."
			}
			
			if ($server.IsClustered -and $dacenabled -eq $false)
			{
				If ($Pscmdlet.ShouldProcess($server.name, "Disabling DAC on clustered instance"))
				{
					Write-Verbose "Setting DAC config back to 0"
					$server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $false
					$server.Configuration.Alter()
				}
			}
			
			$decryptedlogins = New-Object "System.Data.DataTable"
			[void]$decryptedlogins.Columns.Add("Credential")
			[void]$decryptedlogins.Columns.Add("Identity")
			[void]$decryptedlogins.Columns.Add("Password")
			
			# Go through each row in results
			foreach ($cred in $creds)
			{
				# decrypt the password using the service master key and the extracted IV
				$decryptor.Padding = "None"
				$decrypt = $decryptor.Createdecryptor($servicekey, $cred.iv)
				$stream = New-Object System.IO.MemoryStream ( ,$cred.pass)
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
		
		Function Copy-Credential
		{
	<#
		.SYNOPSIS
		Copies Credentials from one server to another using a combination of SMO's .Script() and manual password updates.
		
		.OUTPUT
		System.Data.DataTable
	
	#>
			param (
				[object]$source,
				[object]$destination,
				[System.Management.Automation.PSCredential]$SourceSqlCredential,
				[System.Management.Automation.PSCredential]$DestinationSqlCredential,
				[string[]]$credentials,
				[bool]$force
			)
			
			Write-Output "Collecting Credential logins and passwords on $($sourceserver.name)"
			$sourcecredentials = Get-SqlCredentials $sourceserver
			
			if ($credentials -ne $null)
			{
				$credentiallist = $sourceserver.credentials | Where-Object { $credentials -contains $_.Name }
			}
			else 
			{ 
				$credentiallist = $sourceserver.credentials 
			}
			
			
			Write-Output "Starting migration"
			foreach ($credential in $credentiallist)
			{
				$destserver.credentials.Refresh()
				$credentialname = $credential.name
				
				if ($destserver.credentials[$credentialname] -ne $null)
				{
					if (!$force)
					{
						Write-Warning "$credentialname exists $($destserver.name). Skipping."
						continue
					}
					else
					{
						If ($Pscmdlet.ShouldProcess($destination.name, "Dropping $identity"))
						{
							$destserver.credentials[$credentialname].Drop()
							$destserver.credentials.refresh()
						}
					}
				}
				
				Write-Output "Attempting to migrate $credentialname"
				
				try
				{
					$currentcred = $sourcecredentials | Where-Object { $_.Credential -eq $credentialname }
					$identity = $currentcred.Identity
					$password = $currentcred.Password
					
					If ($Pscmdlet.ShouldProcess($destination.name, "Copying $identity"))
					{
						$sql = "CREATE CREDENTIAL [$credentialname] WITH IDENTITY = N'$identity', SECRET = N'$password'"
						Write-Verbose $sql
						$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
						$destserver.Credentials.Refresh()
						Write-Output "$credentialname successfully copied"
					}
				}
				catch 
				{ 
					Write-Exception $_ 
				}
			}
		}
		
		$credentials = $psboundparameters.credentials
		
		if ($SourceSqlCredential.username -ne $null -or $DestinationSqlCredential.username -ne $null)
		{
			Write-Warning "You are using SQL credentials and this script requires Windows admin access to the server. Trying anyway."
		}
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9)
		{
			throw "Credentials are only supported in SQL Server 2005 and above. Quitting."
		}
		
		Invoke-SmoCheck -SqlServer $sourceserver
		Invoke-SmoCheck -SqlServer $destserver
		
	}
	
	PROCESS
	{
		
		
		Write-Output "Getting NetBios name"
		$sourcenetbios = Resolve-NetBiosName $sourceserver
		
		Write-Output "Checking if remote access is enabled"
		winrm id -r:$sourcenetbios 2>$null | Out-Null
		
		if ($LastExitCode -ne 0) 
		{ 
			throw "Remote PowerShell access not enabled on on $source or access denied. Windows admin acccess required. Quitting." 
		}
		
		Write-Output "Checking if Remote Registry is enabled"
		try 
		{ 
			Invoke-Command -ComputerName $sourcenetbios { Get-ItemProperty -Path "HKLM:\SOFTWARE\" } 
		}
		catch 
		{ 
			throw "Can't connect to remote registry on $source. Quitting." 
		}
		
		Copy-Credential $sourceserver $destserver -Credentials $credentials -force:$force
		
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Credential migration finished" }
	}
}
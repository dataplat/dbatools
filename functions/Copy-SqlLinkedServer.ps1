Function Copy-SqlLinkedServer
{
<# 
.SYNOPSIS 
Copy-SqlLinkedServer migrates Linked Servers from one SQL Server to another. Linked Server logins and passwords are migrated as well.

.DESCRIPTION 
By using password decryption techniques provided by Antti Rantasaari (NetSPI, 2014), this script migrates SQL Server Linked Servers from one server to another, while maintaining username and password.

Credit: https://blog.netspi.com/decrypting-mssql-database-link-server-passwords/
License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER Source
Source SQL Server (2005 and above). You must have sysadmin access to both SQL Server and Windows.

.PARAMETER Destination
Destination SQL Server (2005 and above). You must have sysadmin access to both SQL Server and Windows.

.PARAMETER LinkedServers
Auto-populated list of Linked Servers from Source. If no LinkedServer is specified, all Linked Servers will be migrated.
Note: if spaces exist in the Linked Server name, you will have to type "" or '' around it. I couldn't figure out a way around this.

.PARAMETER Force
By default, if a Linked Server exists on the source and destination, the Linked Server is not copied over. Specifying -force will drop and recreate the Linked Server on the Destination server.

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

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers, Remote Registry & Remote Adminsitration enabled and accessible on source server.
Limitations: Hasn't been tested thoroughly. Works on Win8.1 and SQL Server 2012 & 2014 so far.
This just copies the SQL portion. It does not copy files (ie. a local SQLITE database, or Access Db), nor does it configure ODbC entries.

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlLinkedServer 

.EXAMPLE   
Copy-SqlLinkedServer -Source sqlserver2014a -Destination sqlcluster

Description
Copies all SQL Server Linked Servers on sqlserver2014a to sqlcluster. If Linked Server exists on destination, it will be skipped.

.EXAMPLE   
Copy-SqlLinkedServer -Source sqlserver2014a -Destination sqlcluster -LinkedServers SQL2K5,SQL2k -Force

Description
Copies over two SQL Server Linked Servers (SQL2K and SQL2K2) from sqlserver to sqlcluster. If the credential already exists on the destination, it will be dropped.
#>		
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[switch]$Force,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential
	)
	
	DynamicParam { if ($source) { return (Get-ParamSqlLinkedServers -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	
	BEGIN
	{
		Function Get-LinkedServerLogins
		{
<# 

.SYNOPSIS
Internal function. 
	 
This function is heavily based on Antti Rantasaari's script at http://goo.gl/wpqSib
Antti Rantasaari 2014, NetSPI
License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause

#>
			
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
			if (($servicekey.Length -ne 16) -and ($servicekey.Length -ne 32)) { throw "Unknown key size. Cannot continue. Quitting." }
			
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
			
			$sql = "SELECT sysservers.srvname,syslnklgns.name,substring(syslnklgns.pwdhash,5,$ivlen) iv,substring(syslnklgns.pwdhash,$($ivlen + 5),
	len(syslnklgns.pwdhash)-$($ivlen + 4)) pass FROM master.sys.syslnklgns inner join master.sys.sysservers on syslnklgns.srvid=sysservers.srvid WHERE len(pwdhash)>0"
			
			# Get entropy from the registry
			try
			{
				$logins = Invoke-Command -ComputerName $sourcenetbios -argumentlist $connstring, $sql {
					$connstring = $args[0]; $sql = $args[1]
					$conn = New-Object System.Data.SqlClient.SQLConnection($connstring)
					$conn.open()
					$cmd = New-Object System.Data.SqlClient.SqlCommand($sql, $conn);
					$data = $cmd.ExecuteReader()
					$dt = New-Object "System.Data.DataTable"
					$dt.Load($data)
					$conn.Close()
					$conn.Dispose()
					return $dt
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
			[void]$decryptedlogins.Columns.Add("LinkedServer")
			[void]$decryptedlogins.Columns.Add("Login")
			[void]$decryptedlogins.Columns.Add("Password")
			
			
			# Go through each row in results
			foreach ($login in $logins)
			{
				# decrypt the password using the service master key and the extracted IV
				$decryptor.Padding = "None"
				$decrypt = $decryptor.Createdecryptor($servicekey, $login.iv)
				$stream = New-Object System.IO.MemoryStream ( ,$login.pass)
				$crypto = New-Object System.Security.Cryptography.CryptoStream $stream, $decrypt, "Write"
				
				$crypto.Write($login.pass, 0, $login.pass.Length)
				[byte[]]$decrypted = $stream.ToArray()
				
				# convert decrypted password to unicode
				$encode = New-Object System.Text.UnicodeEncoding
				
				# Print results - removing the weird padding (8 bytes in the front, some bytes at the end)... 
				# Might cause problems but so far seems to work.. may be dependant on SQL server version...
				# If problems arise remove the next three lines.. 
				$i = 8; foreach ($b in $decrypted) { if ($decrypted[$i] -ne 0 -and $decrypted[$i + 1] -ne 0 -or $i -eq $decrypted.Length) { $i -= 1; break; }; $i += 1; }
				$decrypted = $decrypted[8..$i]
				
				[void]$decryptedlogins.Rows.Add($($login.srvname), $($login.name), $($encode.GetString($decrypted)))
			}
			return $decryptedlogins
		}
		
		Function Copy-SqlLinkedServers
		{
<#

.SYNOPSIS
Internal function.

#>
			
			param (
				[object]$source,
				[object]$destination,
				[string[]]$LinkedServers,
				[bool]$force,
				[System.Management.Automation.PSCredential]$SourceSqlCredential,
				[System.Management.Automation.PSCredential]$DestinationSqlCredential
			)
			
			$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
			$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
			
			$source = $sourceserver.name
			$destination = $destserver.name
			
			Write-Output "Collecting Linked Server logins and passwords on $($sourceserver.name)"
			$sourcelogins = Get-LinkedServerLogins $sourceserver
			
			
			if ($LinkedServers -ne $null)
			{
				$serverlist = $sourceserver.LinkedServers | Where-Object { $LinkedServers -contains $_.Name }
			}
			else { $serverlist = $sourceserver.LinkedServers }
			
			Write-Output "Starting migration"
			foreach ($linkedserver in $serverlist)
			{
				$provider = $linkedserver.ProviderName
				try
				{
					$destserver.LinkedServers.Refresh()
					$destserver.LinkedServers.LinkedServerLogins.Refresh()
				}
				catch { }
				
				$linkedservername = $linkedserver.name
				
				if (!$destserver.Settings.OleDbProviderSettings.Name.Contains($provider) -and !$provider.StartsWith("SQLN"))
				{
					Write-Warning "$($destserver.name) does not support the $provider provider. Skipping $linkedservername."
					continue
				}
				
				if ($destserver.LinkedServers[$linkedservername] -ne $null)
				{
					if (!$force)
					{
						Write-Warning "$linkedservername exists $($destserver.name). Skipping."
						continue
					}
					else
					{
						If ($Pscmdlet.ShouldProcess($destination, "Dropping $linkedservername"))
						{
							if ($linkedserver.name -eq 'repl_distributor')
							{
								Write-Warning "repl_distributor cannot be dropped. Not going to try."
								continue
							}
							
							$destserver.LinkedServers[$linkedservername].Drop($true)
							$destserver.LinkedServers.refresh()
						}
					}
				}
				
				Write-Output "Attempting to migrate: $linkedservername"
				If ($Pscmdlet.ShouldProcess($destination, "Migrating $linkedservername"))
				{
					try
					{
						$sql = $linkedserver.Script() | Out-String
						$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
						Write-Verbose $sql
						
						[void]$destserver.ConnectionContext.ExecuteNonQuery($sql)
						$destserver.LinkedServers.Refresh()
						Write-Output "$linkedservername successfully copied"
					}
					catch
					{
						Write-Warning "$linkedservername could not be added to $($destserver.name)"
						Write-Warning "Reason: $($_.Exception)"
						$skiplogins = $true
					}
				}
				
				if ($skiplogins -ne $true)
				{
					$destlogins = $destserver.LinkedServers[$linkedservername].LinkedServerLogins
					$lslogins = $sourcelogins | Where-Object { $_.LinkedServer -eq $linkedservername }
					
					foreach ($login in $lslogins)
					{
						If ($Pscmdlet.ShouldProcess($destination, "Migrating $($login.Login)"))
						{
							$currentlogin = $destlogins | Where-Object { $_.RemoteUser -eq $login.Login }
							
							if ($currentlogin.RemoteUser.length -ne 0)
							{
								try
								{
									$currentlogin.SetRemotePassword($login.Password)
									$currentlogin.Alter()
								}
								catch { Write-Error "$($login.login) failed to copy" }
								
							}
						}
					}
					Write-Output "Finished migrating logins for $linkedservername"
				}
			}
		}
		
	}
	
	PROCESS
	{
		
		$LinkedServers = $psboundparameters.LinkedServers
		
		if ($SourceSqlCredential.username -ne $null -or $DestinationSqlCredential -ne $null)
		{
			Write-Warning "You are using SQL credentials and this script requires Windows admin access to the server. Trying anyway."
		}
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.name
		$destination = $destserver.name
		
		Invoke-SmoCheck -SqlServer $sourceserver
		Invoke-SmoCheck -SqlServer $destserver
		
		if (!(Test-SqlSa -SqlServer $sourceserver -SqlCredential $SourceSqlCredential)) { throw "Not a sysadmin on $source. Quitting." }
		if (!(Test-SqlSa -SqlServer $destserver -SqlCredential $DestinationSqlCredential)) { throw "Not a sysadmin on $destination. Quitting." }
		
		Write-Output "Getting NetBios name"
		$sourcenetbios = Resolve-NetBiosName $sourceserver
		
		Write-Output "Checking if remote access is enabled"
		winrm id -r:$sourcenetbios 2>$null | Out-Null
		if ($LastExitCode -ne 0) { throw "Remote PowerShell access not enabled on $source or access denied. Windows admin acccess required. Quitting." }
		
		Write-Output "Checking if Remote Registry is enabled"
		try { Invoke-Command -ComputerName $sourcenetbios { Get-ItemProperty -Path "HKLM:\SOFTWARE\" } }
		catch { throw "Can't connect to registry on $source. Quitting." }
		
		# Magic happens here
		Copy-SqlLinkedServers $sourceserver $destserver $linkedservers -force:$force
		
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Linked Server migration finished" }
	}
}
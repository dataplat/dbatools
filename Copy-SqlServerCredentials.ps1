<# 
.SYNOPSIS 
Copy-SqlServerCredentials.ps1 migrates SQL Server Credentials from one SQL Server to another, while maintaining Credential passwords.

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

.PARAMETER Force
By default, if a Credential exists on the source and destination, the Credential is not copied over. Specifying -force will drop and recreate the Credential on the Destination server.

.NOTES 
Author  : 	Chrissy LeMaire
Requires: 	PowerShell Version 3.0, SQL Server SMO, 
			Sys Admin access on Windows and SQL Server. DAC access enabled for local (default)
DateUpdated: 2015-May-7
Version: 	0.1.2
Limitations: Hasn't been tested thoroughly. Works on Win8.1 and SQL Server 2012 & 2014 so far.		

.LINK 


.EXAMPLE   
.\Copy-SqlServerCredentials.ps1 -Source sqlserver\instance -Destination sqlcluster

Description
Copies all SQL Server Credentials on sqlserver\instance to sqlcluster. If credentials exist on destination, they will be skipped.

.EXAMPLE   
.\Copy-SqlServerCredentials.ps1 -Source sqlserver -Destination sqlcluster -Credentials "PowerShell Proxy Account" -Force

Description
Copies over one SQL Server Credential (PowerShell Proxy Account) from sqlserver to sqlcluster. If the credential already exists on the destination, it will be dropped and recreated.

#> 
#Requires -Version 3.0
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess = $true)] 

Param(
	# Source SQL Server
	[parameter(Mandatory = $true)]
	[string]$Source,
	
	# Destination SQL Server
	[parameter(Mandatory = $true)]
	[string]$Destination,
	
	[switch]$Force

	)
	
DynamicParam  {
	if ($Source) {
		# Check for SMO and SQL Server access
		if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") -eq $null) {return}
		
		$server = New-Object Microsoft.SqlServer.Management.Smo.Server $source
		$server.ConnectionContext.ConnectTimeout = 2
		try { $server.ConnectionContext.Connect() } catch { return }
	
		# Populate arrays
		$credentiallist = @()
		foreach ($credential in $server.credentials) {
			$credentiallist += $credential.name
		}

		# Reusable parameter setup
		$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
		$attributes = New-Object System.Management.Automation.ParameterAttribute
		
		$attributes.ParameterSetName = "__AllParameterSets"
		$attributes.Mandatory = $false
		
		# Database list parameter setup
		if ($credentiallist) { $dbvalidationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $credentiallist }
		$lsattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
		$lsattributes.Add($attributes)
		if ($credentiallist) { $lsattributes.Add($dbvalidationset) }
		$Credentials = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Credentials", [String[]], $lsattributes)
		
		$newparams.Add("Credentials", $Credentials)			
		$server.ConnectionContext.Disconnect()
	
	return $newparams
	}
}

BEGIN {

Function Get-SQLCredentials { 
	<#
		.SYNOPSIS
		Gets Credential Logins
		 
		This function is heavily based on Antti Rantasaari's script at http://goo.gl/omEOrW
		Antti Rantasaari 2014, NetSPI
		License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause
		
		.OUTPUT
		System.Data.DataTable
	
	#>
		
		param(
		[object]$server
	)
	$sourcename = $server.name
	
	# Query Service Master Key from the database - remove padding from the key
	# key_id 102 eq service master key, thumbprint 3 means encrypted with machinekey
	$sql = "SELECT substring(crypt_property,9,len(crypt_property)-8) FROM sys.key_encryptions WHERE key_id=102 and (thumbprint=0x03 or thumbprint=0x0300000001)"
	try { $smkbytes = $server.ConnectionContext.ExecuteScalar($sql) }
	catch { throw "Can't execute SQL on $sourcename" }
	
	$sourcenetbios = Get-NetBIOSName $server
	$instance = $server.InstanceName
	$serviceInstanceId = $server.serviceInstanceId
	
	# Get entropy from the registry - hopefully finds the right SQL server instance
	try {
		[byte[]]$entropy =  Invoke-Command -ComputerName $sourcenetbios -argumentlist $serviceInstanceId {
		$serviceInstanceId = $args[0]
		$entropy = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$serviceInstanceId\Security\").Entropy 
		return $entropy }
	} catch { throw "Can't access registry keys on $sourcename. Quitting." }

	# Decrypt the service master key
	try {
		$servicekey =  Invoke-Command -ComputerName $sourcenetbios -argumentlist $smkbytes, $Entropy {
		Add-Type -assembly System.Security
		Add-Type -assembly System.Core
		$smkbytes = $args[0]; $Entropy = $args[1]
		$servicekey = [System.Security.Cryptography.ProtectedData]::Unprotect($smkbytes, $Entropy, 'LocalMachine') 
		return $servicekey }
	} catch { throw "Can't unprotect registry data on $($source.name)). Quitting." }

	# Choose the encryption algorithm based on the SMK length - 3DES for 2008, AES for 2012
	# Choose IV length based on the algorithm
	if (($servicekey.Length -ne 16) -and ($servicekey.Length -ne 32)) {
		Write-Warning "Unknown key size. Cannot continue. Quitting."
		return
	}

	if ($servicekey.Length -eq 16) {
		$decryptor = New-Object System.Security.Cryptography.TripleDESCryptoServiceProvider
		$ivlen = 8
	} elseif ($servicekey.Length -eq 32) {
		$decryptor = New-Object System.Security.Cryptography.AESCryptoServiceProvider
		$ivlen = 16
	}

	# Query link server password information from the DB. Remove header from pwdhash, extract IV (as iv) and ciphertext (as pass)
	# Ignore links with blank credentials (integrated auth ?)

	$connstring = "Server=ADMIN:$sourcenetbios\$instance;Trusted_Connection=True"
	$sql = "SELECT name,credential_identity,substring(imageval,5,$ivlen) iv, substring(imageval,$($ivlen+5),len(imageval)-$($ivlen+4)) pass from sys.credentials cred inner join sys.sysobjvalues obj on cred.credential_id = obj.objid where valclass=28 and valnum=2"		
	
	# Get entropy from the registry
	try {
		$creds =  Invoke-Command -ComputerName $sourcenetbios -argumentlist $connstring, $sql {
			$connstring = $args[0]; $sql = $args[1]
			$conn = New-Object System.Data.SqlClient.SQLConnection($connstring)
			$conn.open()
			$cmd = New-Object System.Data.SqlClient.SqlCommand($sql,$conn);
			$data = $cmd.ExecuteReader()
			$dt = New-Object "System.Data.DataTable"
			$dt.Load($data)
			$conn.Close()
			$conn.Dispose()
			return $dt 
		}
	} catch { throw "Can't establish DAC connection to $sourcename from $sourcename. Quitting."}

	$decryptedlogins = New-Object "System.Data.DataTable"
	[void]$decryptedlogins.Columns.Add("Credential")
	[void]$decryptedlogins.Columns.Add("Identity")
	[void]$decryptedlogins.Columns.Add("Password")
	
	# Go through each row in results
	foreach ($cred in $creds) {
		# decrypt the password using the service master key and the extracted IV
		$decryptor.Padding = "None"
		$decrypt = $decryptor.Createdecryptor($servicekey,$cred.iv)
		$stream = New-Object System.IO.MemoryStream (,$cred.pass)
		$crypto = New-Object System.Security.Cryptography.CryptoStream $stream,$decrypt,"Write"

		$crypto.Write($cred.pass,0,$cred.pass.Length)
		[byte[]]$decrypted = $stream.ToArray()

		# convert decrypted password to unicode
		$encode = New-Object System.Text.UnicodeEncoding

		# Print results - removing the weird padding (8 bytes in the front, some bytes at the end)... 
		# Might cause problems but so far seems to work.. may be dependant on SQL server version...
		# If problems arise remove the next three lines.. 
		$i=8; foreach ($b in $decrypted) {if ($decrypted[$i] -ne 0 -and $decrypted[$i+1] -ne 0 -or $i -eq $decrypted.Length) {$i -= 1; break;}; $i += 1;}
		$decrypted = $decrypted[8..$i]
		
		[void]$decryptedlogins.Rows.Add($($cred.name),$($cred.credential_identity),$($encode.GetString($decrypted)))
	}
	return $decryptedlogins
}

Function Copy-SqlServerCredentials { 
	<#
		.SYNOPSIS
		Copies Credentials from one server to another using a combination of SMO's .Script() and manual password updates.
		
		.OUTPUT
		System.Data.DataTable
	
	#>
		
		param(
		[object]$sourceserver,
		[object]$destserver,
		[string[]]$credentials,
		[bool]$force
	)
	
	Write-Warning "Collecting Credential logins and passwords on $($sourceserver.name)"
	$sourcecredentials = Get-SQLCredentials $sourceserver
	
	
	if ($credentials -ne $null) { 
		$serverlist = $sourceserver.credentials | Where-Object { $credentials -contains $_.Name }
	} else { $serverlist = $sourceserver.credentials }
	
	Write-Host "Starting migration" -ForegroundColor Green
	foreach ($credential in $serverlist) {
		$destserver.credentials.Refresh()
		$credentialname = $credential.name
		
		if ($destserver.credentials[$credentialname] -ne $null) { 
			if (!$force) {
				Write-Warning "$credentialname exists $($destserver.name). Skipping." 
				continue
			} else {
				$destserver.credentials[$credentialname].Drop()
				$destserver.credentials.refresh()
			}
		}
		
		Write-Host "Attempting to migrate: $credentialname" -ForegroundColor Yellow
		try {
			$currentcred = $sourcecredentials | Where-Object { $_.Credential -eq $credentialname  }
			$identity = $currentcred.Identity
			$password = $currentcred.Password
			$sql = "CREATE CREDENTIAL [$credentialname] WITH IDENTITY = N'$identity', SECRET = N'$password'"		
			[void]$destserver.ConnectionContext.ExecuteNonQuery($sql) 
			$destserver.credentials.Refresh()
			Write-Host "$credentialname successfully copied." -ForegroundColor Green
		} catch { Write-Warning "$credentialname could not be added to $($destserver.name)" }
	}
}

Function Test-SQLSA      {
 <#
	.SYNOPSIS
	  Ensures sysadmin account access on SQL Server. $server is an SMO server object.

	.EXAMPLE
	  if (!(Test-SQLSA $server)) { throw "Not a sysadmin on $source. Quitting." }  

	.OUTPUTS
		$true if syadmin
		$false if not
	
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$server	
		)
		
try {
		return ($server.Logins[$server.ConnectionContext.trueLogin].IsMember("sysadmin"))
	}
	catch { return $false }
}

Function Get-NetBIOSName {
 <#
	.SYNOPSIS
	Takes a best guess at the NetBIOS name of a server. 

	.EXAMPLE
	$sourcenetbios = Get-NetBIOSName $server
	
	.OUTPUTS
	  String with netbios name.
			
 #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$server
		)

	$servernetbios = $server.ComputerNamePhysicalNetBIOS
	
	if ($servernetbios -eq $null) { $servernetbios = $server.Information.NetName }
	
	if ($servernetbios -eq $null) {
		$servernetbios = ($server.name).Split("\")[0]
		$servernetbios = $servernetbios.Split(",")[0]
	}
	
	return $($servernetbios.ToLower())
}

}

PROCESS {
	if ($credentials.Value -ne $null) {$credentials = @($credentials.Value)}  else {$credentials = $null}

	if ((Get-Host).Version.Major -lt 3) { throw "PowerShell 3.0 and above required." }

	if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") -eq $null )
	{ throw "Quitting: SMO Required. You can download it from http://goo.gl/R4yA6u" }

	if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMOExtended") -eq $null )
	{ throw "Quitting: Extended SMO Required. You can download it from http://goo.gl/R4yA6u" }
	
	Write-Host "Attempting to connect to SQL Servers.."  -ForegroundColor Green
	$sourceserver = New-Object Microsoft.SqlServer.Management.Smo.Server $source
	$destserver = New-Object Microsoft.SqlServer.Management.Smo.Server $destination
	
	try { $sourceserver.ConnectionContext.Connect() } catch { throw "Can't connect to $source or access denied. Quitting." }
	try { $destserver.ConnectionContext.Connect() } catch { throw "Can't connect to $destination or access denied. Quitting." }
		
	if (!(Test-SQLSA $sourceserver)) { throw "Not a sysadmin on $source. Quitting." }
	if (!(Test-SQLSA $destserver)) { throw "Not a sysadmin on $destination. Quitting." }
	
	$sourcenetbios = Get-NetBIOSName $sourceserver
	
	# Test for WinRM
	try { $result = Test-WSMan -ComputerName $sourcenetbios } catch { throw "Remote PowerShell access not enabled on on $source. Quitting." }
	
	# Test for registry access
	try { Invoke-Command -ComputerName $sourcenetbios { Get-ItemProperty -Path "HKLM:\SOFTWARE\" } } 
	catch { throw "Can't connect to registry on $source. Quitting." }
	
	# Magic happens here
	Copy-SqlServerCredentials $sourceserver $destserver $credentials $force
	
}

END {
	$sourceserver.ConnectionContext.Disconnect()
	$destserver.ConnectionContext.Disconnect()
	Write-Host "Script completed" -ForegroundColor Green
}

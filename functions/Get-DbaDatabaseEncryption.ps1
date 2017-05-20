function Get-DbaDatabaseEncryption {
<#
.SYNOPSIS
Returns a summary of encrption used on databases based to it.

.DESCRIPTION
Shows if a database has Transparaent Data encrption, any certificates, asymmetric keys or symmetric keys with details for each.

.PARAMETER SqlInstance
SQLServer name or SMO object representing the SQL Server to connect to. This can be a
collection and recieve pipeline input

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, currend Windows login will be used.

.PARAMETER Database
The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

.PARAMETER Exclude
The database(s) to exclude - this list is autopopulated from the server

.PARAMETER IncludeSystemDBs
Switch parameter that when used will display system database information
	
.PARAMETER Silent 
Use this switch to disable any kind of verbose messages
	
.NOTES 
Original Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Get-DbaDatabaseEncryption

.EXAMPLE
Get-DbaDatabaseEncryption -SqlInstance DEV01
List all encrpytion found on the instance by database

.EXAMPLE
Get-DbaDatabaseEncryption -SqlInstance DEV01 -Database MyDB
List all encrption found in MyDB 
#>
	[CmdletBinding()]
	param ([parameter(ValueFromPipeline, Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$Exclude,
		[switch]$IncludeSystemDBs,
		[switch]$Silent
	)
	
	process {
		foreach ($instance in $SqlInstance) {
			#For each SQL Server in collection, connect and get SMO object
			Write-Verbose "Connecting to $instance"
			
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failed to connect to: $instance" -Continue -Target $instance
			}
			
			#If IncludeSystemDBs is true, include systemdbs
			#only look at online databases (Status equal normal)
			try {
				if ($database.length -gt 0) {
					$dbs = $server.Databases | Where-Object { $database -contains $_.Name }
				}
				elseif ($IncludeSystemDBs) {
					$dbs = $server.Databases | Where-Object { $_.status -eq 'Normal' }
				}
				else {
					$dbs = $server.Databases | Where-Object { $_.status -eq 'Normal' -and $_.IsSystemObject -eq 0 }
				}
				
				if ($exclude.length -gt 0) {
					$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
				}
			}
			catch {
				Stop-Function -Message "Unable to gather dbs for $instance" -Target $instance -Continue
			}
			
			foreach ($db in $dbs) {
				Write-Message -Level Verbose -Message "Processing $db"
				
				if ($db.EncryptionEnabled -eq $true) {
					[PSCustomObject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.DomainInstanceName
						Database = $db.Name
						Encryption = "EncryptionEnabled (tde)"
						Name = $null
						LastBackup = $null
						PrivateKeyEncryptionType = $null
						EncryptionAlgorithm = $null
						KeyLength = $null
						Owner = $null
						Object = $null
					}
					
				}
				
				foreach ($cert in $db.Certificates) {
					[PSCustomObject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.DomainInstanceName
						Database = $db.Name
						Encryption = "Certificate"
						Name = $cert.Name
						LastBackup = $cert.LastBackupDate
						PrivateKeyEncryptionType = $cert.PrivateKeyEncryptionType
						EncryptionAlgorithm = $null
						KeyLength = $null
						Owner = $cert.Owner
						Object = $cert
					}
					
				}
				
				foreach ($ak in $db.AsymmetricKeys) {
					[PSCustomObject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.DomainInstanceName
						Database = $db.Name
						Encryption = "Asymentric key"
						Name = $ak.Name
						LastBackup = $null
						PrivateKeyEncryptionType = $ak.PrivateKeyEncryptionType
						EncryptionAlgorithm = $ak.KeyEncryptionAlgorithm
						KeyLength = $ak.KeyLength
						Owner = $ak.Owner
						Object = $ak
					}
					
				}
				foreach ($sk in $db.SymmetricKeys) {
					[PSCustomObject]@{
						Server = $server.name
						Instance = $server.InstanceName
						Database = $db.Name
						Encryption = "Symmetric key"
						Name = $sk.Name
						LastBackup = $null
						PrivateKeyEncryptionType = $sk.PrivateKeyEncryptionType
						EncryptionAlgorithm = $ak.EncryptionAlgorithm
						KeyLength = $sk.KeyLength
						Owner = $sk.Owner
						Object = $sk
					}
				}
			}
		}
	}
}


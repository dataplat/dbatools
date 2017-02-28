function Get-DbaDatabaseEncryption {
	[CmdletBinding()]
	param ([parameter(ValueFromPipeline, Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$IncludeSystemDBs)
	
	DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $SourceSqlCredential } }
	
	BEGIN
	{
		$databases = $psboundparameters.Databases
        $exclude = $psboundparameters.Exclude
    }

	PROCESS
	{
		foreach ($s in $SqlServer)
		{
			#For each SQL Server in collection, connect and get SMO object
			Write-Verbose "Connecting to $s"
			$server = Connect-SqlServer $s -SqlCredential $SqlCredential
			#If IncludeSystemDBs is true, include systemdbs
			#only look at online databases (Status equal normal)
			try
			{
				if ($databases.length -gt 0)
				{
					$dbs = $server.Databases | Where-Object { $databases -contains $_.Name }
				}
				elseif ($IncludeSystemDBs)
				{
					$dbs = $server.Databases | Where-Object { $_.status -eq 'Normal' }
				}
				else
				{
					$dbs = $server.Databases | Where-Object { $_.status -eq 'Normal' -and $_.IsSystemObject -eq 0 }
				}
				
				if ($exclude.length -gt 0)
				{
					$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
				}
			}
			catch
			{
				Write-Exception $_
				throw "Unable to gather dbs for $($s.name)"
				continue
			}
			
			foreach ($db in $dbs)
			{    
                if ($db.EncryptionEnabled -eq $true)
                {
       
                [PSCustomObject]@{
                        Server = $server.name
                        Instance = $server.InstanceName
                        Database = $db
                        Encryption = "EncryptionEnabled (tde)"
                        Name =  $null
                        LastBackup = $null 
                        PrivateKeyEncryptionType = $null
                        EncryptionAlgorithm = $null
                        KeyLength = $null
                        Owner = $null			
                    } 
                   
                }

                foreach ($cert in $db.Certificates)
                {
    
                    [PSCustomObject]@{
                        Server = $server.name
                        Instance = $server.InstanceName
                        Database = $db
                        Encryption = "Certificate"
                        Name =  $cert.Name
                        LastBackup = $cert.LastBackupDate
                        PrivateKeyEncryptionType = $cert.PrivateKeyEncryptionType
                        EncryptionAlgorithm = $null
                        KeyLength = $null
                        Owner = $cert.Owner			
                    }
                    
                }
                
                foreach ($ak in $db.AsymmetricKeys)
                {
  
                    [PSCustomObject]@{
                        Server = $server.name
                        Instance = $server.InstanceName
                        Database = $db
                        Encryption = "Asymentric key"
                        Name =  $ak.Name
                        LastBackup = $null
                        PrivateKeyEncryptionType = $ak.PrivateKeyEncryptionType
                        EncryptionAlgorithm = $ak.KeyEncryptionAlgorithm
                        KeyLength = $ak.KeyLength
                        Owner = $ak.Owner	
                    }
                    
                }
                foreach ($sk in $db.SymmetricKeys)
                {

                    [PSCustomObject]@{
                        Server = $server.name
                        Instance = $server.InstanceName
                        Database = $db
                        Encryption = "Symmetric key"
                        Name =  $sk.Name
                        LastBackup = $null
                        PrivateKeyEncryptionType = $sk.PrivateKeyEncryptionType
                        EncryptionAlgorithm = $ak.EncryptionAlgorithm
                        KeyLength = $sk.KeyLength
                        Owner = $sk.Owner	
                    }
                }
            }
        }  
    }		
}


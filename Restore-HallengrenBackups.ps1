<# 
 .SYNOPSIS 
    Restores SQL Server databases from the backup directory structure created by Ola Hallengren's database maintenance scripts.

 .DESCRIPTION 
    Many SQL Server database administrators use Ola Hallengren's SQL Server Maintenance Solution which can be found at http://ola.hallengren.com
	Hallengren uses a predictable backup structure which made it relatively easy to create a script that can restore an entire SQL Server database instance, down to the master database (next version), to a new server. This script is intended to be used in the event that the originating SQL Server becomes unavailable, thus rendering my other SQL restore script (http://goo.gl/QmfQ6s) ineffective.
	
 .PARAMETER ServerName
	Required. The SQL Server to which you will be restoring the databases.

 .PARAMETER RestoreFromDirectory
	Required. The directory that contains the database backups (ex. \\fileserver\share\sqlbackups\SQLSERVERA)

.PARAMETER ReuseFolderStructure
	Restore-HallengrenBackups.ps1 will restore to the default user data and log directories, unless this switch is used. Useful if you're restoring from a server that had a complex db file structure.

.PARAMETER IncludeDBs
  Migrates ONLY specified databases. This list is auto-populated for tab completion.
  
.PARAMETER ExcludeDBs
	Excludes specified databases from migration. This list is auto-populated for tab completion.
 
.PARAMETER Force
	Will overwrite any existing databases on $ServerName. 
	
 .NOTES 
    Author  : Chrissy LeMaire
    Requires: PowerShell Version 3.0, SMO, sysadmin access on destination SQL Server.
	Version: 0.2.2

 .LINK 
  	http://gallery.technet.microsoft.com/scriptcenter/Restore-SQL-Backups-cd958ec1

 .EXAMPLE   
.\Restore-HallengrenBackups.ps1 -ServerName sqlcluster -RestoreFromDirectory \\fileserver\share\sqlbackups\SQLSERVER2014A

Description

All user databases contained within \\fileserver\share\sqlbackups\SQLSERVERA will be restored to sqlcluster, down the most recent full/differential/logs.

#> 
#Requires -Version 3.0
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess = $true)] 

Param(
	[parameter(Mandatory = $true)]
	[string]$ServerName,
	[parameter(Mandatory = $true)]
	[string]$RestoreFromDirectory,
	[parameter(Mandatory = $false)]
	[switch]$ReuseFolderStructure,
	[parameter(Mandatory = $false)]
	[switch]$force
	
	)

DynamicParam  {
	
	if ($RestoreFromDirectory) {		
		$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
		$paramattributes = New-Object System.Management.Automation.ParameterAttribute
		$paramattributes.ParameterSetName = "__AllParameterSets"
		$paramattributes.Mandatory = $false
		$systemdbs = @("master","msdb","model")
		$argumentlist = (Get-ChildItem -Path $RestoreFromDirectory -Directory).Name | Where-Object { $systemdbs -notcontains $_ }
		$validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $argumentlist
		$combinedattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
		$combinedattributes.Add($paramattributes)
		$combinedattributes.Add($validationset)
		$IncludeDBs = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("IncludeDBs", [String[]], $combinedattributes)
		$ExcludeDBs = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("ExcludeDBs", [String[]], $combinedattributes)
		$newparams.Add("IncludeDBs", $IncludeDBs)
		$newparams.Add("ExcludeDBs", $ExcludeDBs)
		return $newparams
	}
}


BEGIN {

Function Drop-SQLDatabase {
 <#
            .SYNOPSIS
             Uses SMO's KillDatabase to drop all user connections then drop a database. $server is
			 an SMO server object.

            .EXAMPLE
              Drop-SQLDatabase $server $dbname

            .OUTPUTS
                $true if success
                $false if failure
			
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[object]$server,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[string]$dbname
		)
		
	try {
		$server.KillDatabase($dbname)
		$server.refresh()
		Write-Host "Successfully dropped $dbname on $($server.name)." -ForegroundColor Green
		return $true
	}
	catch {	return $false }
}

Function Get-SQLFileStructures {
 <#
            .SYNOPSIS
             Dictionary object that contains file structures for SQL databases
			
            .EXAMPLE
            $filestructure = Get-SQLFileStructures $server $dbname $filelist $ReuseFolderstructure
			foreach	($file in $filestructure.values) {
				Write-Host $file.physical
				Write-Host $file.logical
				Write-Host $file.remotepath
			}

            .OUTPUTS
             Dictionary
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true,Position=0)]
			[ValidateNotNullOrEmpty()]
			[object]$server,
			
			[Parameter(Mandatory = $true,Position=1)]
			[string]$dbname,
			
			[Parameter(Mandatory = $true,Position=2)]
			[object]$filelist,
			
			[Parameter(Mandatory = $false,Position=3)]
			[bool]$ReuseFolderstructure
		)
	
	$destinationfiles = @{};
	$logfiles = $filelist | Where-Object {$_.Type -eq "L"}
	$datafiles = $filelist | Where-Object {$_.Type -ne "L"}
	$filestream = $filelist | Where-Object {$_.Type -eq "S"}
	
	if ($filestream) {
		$sql = "select coalesce(SERVERPROPERTY('FilestreamConfiguredLevel'),0) as fs"
		$fscheck = $server.databases['master'].ExecuteWithResults($sql)
		if ($fscheck.tables.fs -eq 0)  { return $false }
	}
	
	# Data Files
	foreach ($file in $datafiles) {
		# Destination File Structure
		$d = @{}
		if ($ReuseFolderstructure -eq $true) {
			$d.physical = $file.PhysicalName
		} else {
			$directory = Get-SQLDefaultPaths $server data
			$filename = Split-Path $($file.PhysicalName) -leaf		
			$d.physical = "$directory\$filename"
		}
		
		$d.logical = $file.LogicalName
		$destinationfiles.add($file.LogicalName,$d)
	}
	
	# Log Files
	foreach ($file in $logfiles) {
		$d = @{}
		if ($ReuseFolderstructure) {
			$d.physical = $file.PhysicalName
		} else {
			$directory = Get-SQLDefaultPaths $server log
			$filename = Split-Path $($file.PhysicalName) -leaf		
			$d.physical = "$directory\$filename"
		}
		
		$d.logical = $file.LogicalName
		$destinationfiles.add($file.LogicalName,$d)
	}

	return $destinationfiles
}

Function Get-SQLDefaultPaths     {
 <#
            .SYNOPSIS
			Gets the default data and log paths for SQL Server. Needed because SMO's server.defaultpath is sometimes null.

            .EXAMPLE
            $directory = Get-SQLDefaultPaths $server data
			$directory = Get-SQLDefaultPaths $server log

            .OUTPUTS
              String with file path.
			
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$server,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [string]$filetype
		)
		
	switch ($filetype) { "mdf" { $filetype = "data" } "ldf" {  $filetype = "log" } }
	
	if ($filetype -eq "log") {
		# First attempt
		$filepath = $server.DefaultLog
		# Second attempt
		if ($filepath.Length -eq 0) { $filepath = $server.Information.MasterDBLogPath }
		# Third attempt
		if ($filepath.Length -eq 0) {
			$sql = "select SERVERPROPERTY('InstanceDefaultLogPath') as physical_name"
			$filepath = $server.ConnectionContext.ExecuteScalar($sql)
		}
	} else {
		# First attempt
		$filepath = $server.DefaultFile
		# Second attempt
		if ($filepath.Length -eq 0) { $filepath = $server.Information.MasterDBPath }
		# Third attempt
		if ($filepath.Length -eq 0) {
			 $sql = "select SERVERPROPERTY('InstanceDefaultDataPath') as physical_name"
			 $filepath = $server.ConnectionContext.ExecuteScalar($sql)
		}
	}
	
	if ($filepath.Length -eq 0) { throw "Cannot determine the required directory path." }
	$filepath = $filepath.TrimEnd("\")
	return $filepath
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

Function Restore-SQLDatabase {
        <#
            .SYNOPSIS
             Restores .bak file to SQL database. Creates db if it doesn't exist. $filestructure is
			a custom object that contains logical and physical file locations.

            .EXAMPLE
			 $filestructure = Get-SQLFileStructures $sourceserver $destserver $ReuseFolderstructure
             Restore-SQLDatabase $destserver $dbname $backupfile $filetype   

            .OUTPUTS
                $true if success
                $true if failure
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
			[object]$server,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [string]$dbname,

			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [string]$backupfile,
		
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [string]$filetype,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$filestructure

        )
		
	$servername = $server.name
	$server.ConnectionContext.StatementTimeout = 0
	$restore = New-Object "Microsoft.SqlServer.Management.Smo.Restore"
	$restore.ReplaceDatabase = $true
	
	foreach	($file in $filestructure.values) {
		$movefile = New-Object "Microsoft.SqlServer.Management.Smo.RelocateFile" 
		$movefile.LogicalFileName = $file.logical
		$movefile.PhysicalFileName = $file.physical
		$null = $restore.RelocateFiles.Add($movefile)
	}
	
	try {
		
		$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] { 
			Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent)) 
		}
		$restore.add_PercentComplete($percent)
		$restore.PercentCompleteNotification = 1
		$restore.add_Complete($complete)
		$restore.ReplaceDatabase = $true
		$restore.Database = $dbname
		$restore.Action = $filetype
		$restore.NoRecovery = $true
		$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
		$device.name = $backupfile
		$device.devicetype = "File"
		$restore.Devices.Add($device)
		
		Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
		$restore.sqlrestore($servername)
		Write-Progress -id 1 -activity "Restoring $dbname to $servername" -status "Complete" -Completed
		
		return $true
	} catch {
		$x = $_.Exception
		Write-Warning "Restore failed: $x"
		return $false
	}
}


}

PROCESS { 
	
	<# ----------------------------------------------------------
		Sanity Checks
			- Is SMO available?
			- Is the SQL Server reachable?
			- Is the account running this script an admin?
			- Is SQL Version >= 2000?
			- Is $RestoreFromDirectory valid?
	---------------------------------------------------------- #>

	if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") -eq $null )
	{ throw "Quitting: SMO Required. You can download it from http://goo.gl/R4yA6u" }

	if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMOExtended") -eq $null )
	{ throw "Quitting: Extended SMO Required. You can download it from http://goo.gl/R4yA6u" }


	if (!([string]::IsNullOrEmpty($RestoreFromDirectory))) {
		if (!($RestoreFromDirectory.StartsWith("\\"))) {
			throw "RestoreFromDirectory must be a valid UNC path (\\server\share)." 
		}
		
		if (!(Test-Path $RestoreFromDirectory)) {
			throw "$RestoreFromDirectory does not exist or cannot be accessed." 
		}
	}
	
	Write-Host "Attempting to connect to SQL Server.."  -ForegroundColor Green
	$server = New-Object Microsoft.SqlServer.Management.Smo.Server $ServerName
	try { $server.ConnectionContext.Connect() } catch { throw "Can't connect to $ServerName. Quitting." }
	$server.ConnectionContext.StatementTimeout = 0
	
	if (!(Test-SQLSA $server)) { throw "Not a sysadmin on $ServerName. Quitting." }
	
	if ($sourceserver.versionMajor -lt 8 -and $server.versionMajor -lt 8) {
		throw "This script can only be run on SQL Server 2000 and above. Quitting." 
	}

	if ($sourceserver.versionMajor -eq 8 -and $IncludeSystemDBs) {
		throw "Migrating system databases not supported in SQL Server 2000." 
	}
	
	# Convert from RuntimeDefinedParameter  object to regular array
	if ($IncludeDBs.Value -ne $null) {$IncludeDBs = @($IncludeDBs.Value)}  else {$IncludeDBs = $null}
	if ($ExcludeDBs.Value -ne $null) {$ExcludeDBs = @($ExcludeDBs.Value)}  else {$ExcludeDBs = $null}
	
	$dblist = @(); $skippedb = @{}; $migrateddb = @{};
	$systemdbs = @("master","msdb","model")
	

	$subdirectories = (Get-ChildItem -Directory $RestoreFromDirectory).FullName
	foreach ($subdirectory in $subdirectories)  {
		if ((Get-ChildItem $subdirectory).Name -eq "FULL") { $dblist += $subdirectory; continue }
	}
	
	if ($dblist.count -eq 0) { 
		throw "No databases to restore. Did you use the correct file path? Format should be \\fileshare\share\sqlbackups\sqlservername"
	}
	
	foreach ($db in $dblist) {
		$dbname = Split-Path $db -leaf
		if ($systemdbs -contains $dbname) { continue }
		if (!([string]::IsNullOrEmpty($IncludeDBs)) -and $IncludeDBs -notcontains $dbname) { continue }
		if (!([string]::IsNullOrEmpty($ExcludeDBs)) -and $ExcludeDBs -contains $dbname) { 
			 $skippedb.Add($dbname,"Explicitly Skipped")
			 Continue
		}
		if ($systemdbs -contains $dbname) { continue }

		if ($server.databases[$dbname] -ne $null -and !$force -and $systemdbs -notcontains $dbname) {
			Write-Warning "$dbname exists at $ServerName. Use -Force to drop and migrate."
			$skippedb[$dbname] = "Database exists at $ServerName. Use -Force to drop and migrate."
			continue
		}
		
		if ($server.databases[$dbname] -ne $null -and $force -and $systemdbs -notcontains $dbname) {
				If ($Pscmdlet.ShouldProcess($servername,"DROP DATABASE $dbname")) {
					Write-Host "$dbname already exists. -Force was specified. Dropping $dbname on $servername." -ForegroundColor Yellow
					$dropresult = Drop-SQLDatabase $server $dbname
					if (!$dropresult) { $skippedb[$dbname] = "Database exists and could not be dropped."; continue }
				}
		}
		
		$full = Get-ChildItem "$db\FULL\*.bak" | sort LastWriteTime | select -last 1
		$since = $full.LastWriteTime; $full = $full.FullName
		
		$diff = $null; $logs = $null
		if (Test-Path  "$db\DIFF"){
			$diff = Get-ChildItem "$db\DIFF\*.bak" | Where { $_.LastWriteTime -gt $since } | sort LastWriteTime | select -last 1
			$since = $diff.LastWriteTime; $diff = $diff.fullname
		}
		if (Test-Path  "$db\LOG"){
			$logs = (Get-ChildItem "$db\LOG\*.trn" | Where { $_.LastWriteTime -gt $since })
			$logs = ($logs | Sort-Object LastWriteTime).Fullname
		}
		
		$restore = New-Object "Microsoft.SqlServer.Management.Smo.Restore"
		$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem $full, "FILE"
		$restore.Devices.Add($device)
		try { $filelist = $restore.ReadFileList($server) }
		catch { throw "File list could not be determined. This is likely due to connectivity issues with the SQL Server, the database version is incorrect, or the SQL Server service account does not have access to the file share. Script terminating." }
			
		$filestructure = Get-SQLFileStructures $server $dbname $filelist $ReuseFolderstructure
		
		if ($filestructure -eq $false) { 
			Write-Warning "$dbname contains FILESTREAM and filestreams are not supported by destination server. Skipping."
			$skippedb[$dbname] = "Database contains FILESTREAM and filestreams are not supported by destination server."
			continue
		}
		$backupinfo = $restore.ReadBackupHeader($server)
		$backupversion = [version]("$($backupinfo.SoftwareVersionMajor).$($backupinfo.SoftwareVersionMinor).$($backupinfo.SoftwareVersionBuild)")
	
		Write-Host "Restoring FULL backup to $dbname to $servername" -ForegroundColor Yellow
		$result = Restore-SQLDatabase $server $dbname $full "Database" $filestructure

		if ($result -eq $true){
			if ($diff) {
				Write-Host "Restoring DIFFERENTIAL backup" -ForegroundColor Yellow
				$result = Restore-SQLDatabase $server $dbname $diff "Database" $filestructure 
				if ($result -ne $true) { $result | fl -force ; return}
			}
			if ($logs) { 
				Write-Host "Restoring $($logs.count) LOGS" -ForegroundColor Yellow
				foreach ($log in $logs) { 
				$result = Restore-SQLDatabase $server $dbname $log "Log" $filestructure } 
			}
		}
		
		if ($result -eq $false) { Write-Warning "$dbname could not be restored."; continue }
		
		$sql = "RESTORE DATABASE [$dbname] WITH RECOVERY"
		try { 
			$server.databases['master'].ExecuteNonQuery($sql)
			$migrateddb.Add($dbname,"Successfully restored.")
			Write-Host "Successfully restored $dbname." -ForegroundColor Green
		} catch { Write-Warning "$dbname could not be restored." }
		
		try {
			$server.databases.refresh()
			$server.databases[$dbname].SetOwner('sa')
			$server.databases[$dbname].Alter()
			Write-Host "Successfully change $dbname dbowner to sa" -ForegroundColor Green
		} catch { Write-Warning "Could not update dbowner to sa." }
		
		
	} #end of for each database folder
	
	$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
	$csvfilename = "$($server.name.replace('\','$'))-$timenow"
	$migrateddb.GetEnumerator() | Sort-Object Value; $skippedb.GetEnumerator() | Sort-Object Value
	$migrateddb.GetEnumerator() | Sort-Object Value | Select Name, Value | Export-Csv -Path "$csvfilename-db.csv" -NoTypeInformation
}

END {
#Clean up
$server.ConnectionContext.Disconnect()
Write-Host "Script completed" -ForegroundColor Green
}

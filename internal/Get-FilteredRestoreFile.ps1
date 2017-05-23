function Get-FilteredRestoreFile
{
<#
.SYNOPSIS
Internal Function to Filter a set of SQL Server backup files

.DESCRIPTION
Takes an array of FileSystem Objects and then filters them down by date to get a potential Restore set
First step is to pass them to a SQLInstance to be parsed with Read-DBABackupHeader
The we find the last full backup before the RestorePoint.
Then filter for and Diff backups between the full backup and the RestorePoint
Tnen find the T-log backups needed to bridge the gap up until the RestorePoint
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$Files,
        [parameter(Mandatory = $true)]
        [object]$SqlServer,
        [DateTime]$RestoreTime = (Get-Date).addyears(1),
        [System.Management.Automation.PSCredential]$SqlCredential,
        [switch]$IgnoreLogBackup,
        [switch]$TrustDbBackupHistory,
        [switch]$Continue,
        [object]$ContinuePoints,
        [string]$DatabaseName

	)
    Begin
    {
        $FunctionName =(Get-PSCallstack)[0].Command
        Write-Verbose "$FunctionName - Starting"

        $allsqlBackupDetails = @()
        $OutResults = @()
        $InternalFiles = @()
    }
    # -and $_.BackupStartDate -lt $RestoreTime
    process
        {

        foreach ($file in $files){
            $InternalFiles += $file
        }
    }
    End
    {

   
        if ($TrustDbBackupHistory)
        {
            Write-Verbose "$FunctionName - Trusted backup history loop"

            $tmpInternalFiles = @()
            foreach ($row in $InternalFiles)
            {
                if ($row.FullName.Count -gt 1){
                    foreach ($filename in $row.FullName)
                    {
                        $newIF  = $row | select *
                        $NewIf.fullName = $filename.ToString()
                        $NewIf.BackupPath = $filename.ToString()
                        $tmpInternalFiles += $NewIf
                    }
                }
                else
                {
                    $tmpInternalFiles += $row
                }
            }
            $InternalFiles = $tmpInternalFiles 

            $allsqlBackupDetails += $InternalFiles | Where-Object {$_.Type -eq 'Full'} | select-object *,  @{Name="BackupTypeDescription";Expression={"Database"}},  @{Name="BackupType";Expression={"1"}}
            $allsqlBackupDetails += $InternalFiles | Where-Object {$_.Type -eq 'Log'} | select-object *,  @{Name="BackupTypeDescription";Expression={"Transaction Log"}},  @{Name="BackupType";Expression={"2"}}
            $allsqlBackupDetails += $InternalFiles | Where-Object {$_.Type -eq 'Differential'} | select-object *,  @{Name="BackupTypeDescription";Expression={"Database Differential"}},  @{Name="BackupType";Expression={"5"}}
        }
        else
        {
    		Write-Verbose "$FunctionName - Read File headers (Read-DBABackupHeader)"		
			$AllSQLBackupdetails = $InternalFiles | ForEach-Object{if($_.fullname -ne $null){$_.Fullname}else{$_}} | Read-DBAbackupheader -sqlserver $SQLSERVER -SqlCredential $SqlCredential
        }

		Write-Verbose "$FunctionName - $($AllSQLBackupdetails.count) Files to filter"
        $Databases = $AllSQLBackupdetails  | Group-Object -Property Servername, DatabaseName
        Write-Verbose "$FunctionName - $(($Databases | Measure-Object).count) database to process"

        if ($Continue)
        {
            IF ($DatabaseName -ne '')
            {
                if (($Databases | Measure-Object).count -gt 1)
                {
                    Write-Warning "More than 1 db restore for 1 db - exiting"
                    return
                }else{
                    $dbrec = $DatabaseName
                }
                
            }
            else
            {
                Write-Verbose "Continue set, so filtering to these databases :$($continuePoints.Database -join ',')"
                #$ignore = $Databases | Where-Object {$_.DatabaseName -notin ($continuePoints.Database)} | select-Object DatabaseName
                #Write-Verbose "Ignoring these: $($ignore -join ',')"
                $Databases = $Databases | Where-Object {(($_.Name -split ',')[1]).trim() -in ($continuePoints.Database)}
                Write-verbose "$databases"
            }
        } 
		
		foreach ($Database in $Databases){

            $Results = @()
            Write-Verbose "$FunctionName - Find Newest Full backup - $($_.DatabaseName)"

                $ServerName, $databaseName = $Database.Name.split(',').trim()
               # $databasename = 'restoretimeclean'
               if ($null -ne $dbrec)
               {
                $DatabaseName = $dbrec
               }
            $SQLBackupdetails = $AllSQLBackupdetails | Where-Object {$_.ServerName -eq $ServerName -and $_.DatabaseName -eq $DatabaseName.trim()}
            #If we're continuing a restore, then we aren't going to be needing a full backup....
            $TlogStartlsn = 0
            if (!($continue))
            {
                $Fullbackup = $SQLBackupdetails | where-object {$_.BackupTypeDescription -eq 'Database' -and $_.BackupStartDate -lt $RestoreTime} | Sort-Object -Property BackupStartDate -descending | Select-Object -First 1
                if ($Fullbackup -eq $null)
                {
                    Write-Warning "$FunctionName - No Full backup found to anchor the restore" 
                    break
                }
                #This scans for striped full backups to build the results
                $Results += $SQLBackupdetails | where-object {$_.BackupTypeDescription -eq "Database" -and $_.FirstLSN -eq $FullBackup.FirstLSN}
            }
            else
            {
                Write-Verbose "Continueing"
                $Fullbackup = $ContinuePoints| Where-Object {$_.Database -eq $DatabaseName}
                $TLogStartLsn = $Fullbackup.redo_start_lsn
                
            }    
            Write-Verbose "$FunctionName - Got a Full backup, now to find diffs if they exist"
            
            #Get latest Differential Backup
            #If we're doing a continue and the last restore wasn't a full db we can't use a diff, so skip
            if ($null -eq $lastrestore -or $lastrestore -eq 'Database'  )
            {
                $DiffbackupsLSN = ($SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Database Differential' -and $_.DatabaseBackupLSN -eq $Fullbackup.FirstLsn -and $_.BackupStartDate -lt $RestoreTime} | Sort-Object -Property BackupStartDate -descending | Select-Object -First 1).FirstLSN
                #Scan for striped differential backups
                $Diffbackups = $SqlBackupDetails | Where-Object {$_.BackupTypeDescription -eq 'Database Differential' -and $_.DatabaseBackupLSN -eq $Fullbackup.FirstLsn -and $_.FirstLSN -eq $DiffBackupsLSN}
                if ($null -ne $Diffbackups){
                    Write-Verbose "$FunctionName - we have at least one diff so look for tlogs after the last one"
                    #If we have a Diff backup, we only need T-log backups post that point
                    $TlogStartLSN = ($DiffBackups | select-object -Property FirstLSN -first 1).FirstLSN
                    $Results += $Diffbackups
                }
            }
            
            if ($FullBackup.RecoverModel -eq 'SIMPLE' -or $IgnoreLogBackup)
            {
                Write-Verbose "$FunctionName - Database in simple mode or IgnoreLogBackup is true, skipping Transaction logs"
            }
            else
            {
 
                write-verbose " frfID - $($Fullbackup.FirstRecoveryForkID)"
                write-verbose "tstart - $TlogStartLSN"
                Write-Verbose "$FunctionName - Got a Full/Diff backups, now find all Tlogs needed"
                $AllTlogs = $SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log'} 
                $Filteredlogs = $SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log' -and $_.FirstRecoveryForkID -eq $Fullbackup.FirstRecoveryForkID -and $_.LastLSN -gt $TlogStartLSN -and $_.BackupStartDate -lt $RestoreTime}
                # -and $_.BackupStartDate -ge $LogStartDate
                $GroupedLogs = $FilteredLogs | Group-Object -Property LastLSN, FirstLSN
                
                #$AllTlogs
                #return
                $Tlogs = @()
                foreach ($LogGroup in $GroupedLogs)
                {
                    $Tlogs += $LogGroup.Group | Where-Object {$_.BackupSetGUID -eq ($LogGroup.Group | sort-Object -Property BackupStartDate -Descending | select-object -first 1).BackupSetGUID}
                }
                Write-Verbose "$FunctionName - Filtered $($Alltlogs.count) log backups down to $($Tlogs.count)"
                $Results += $Tlogs
                #Catch the last Tlog that covers the restore time!
                $Tlogfinal = $SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log' -and $_.BackupStartDate -gt $RestoreTime} | Sort-Object -Property LastLSN  | Select-Object -First 1
                $Results += $Tlogfinal
                $TlogCount = ($Results | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log'}).count
                Write-Verbose "$FunctionName - $TLogCount Transaction Log backups found"
            }
            Write-Verbose "$FunctionName - Returning Results to caller"
            $OutResults += @([PSCustomObject]@{ID=$DatabaseName;values=$Results})
        }
        $OutResults
    }
}

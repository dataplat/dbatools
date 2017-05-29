#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

function Get-FilteredRestoreFile {
    <#
        .SYNOPSIS
            Internal Function to Filter a set of SQL Server backup files
        
        .DESCRIPTION
            Takes an array of FileSystem Objects and then filters them down by date to get a potential Restore set
            First step is to pass them to a SQLInstance to be parsed with Read-DBABackupHeader
            The we find the last full backup before the RestorePoint.
            Then filter for and Diff backups between the full backup and the RestorePoint
            Tnen find the T-log backups needed to bridge the gap up until the RestorePoint
        
        .PARAMETER Files
            The files to filter
        
        .PARAMETER SqlInstance
            The Sql Instance from which the backup headers are retrieved for comparison.
        
        .PARAMETER RestoreTime
            The time constraint between backup time and up to when the transaction logs are retrieved.
        
        .PARAMETER SqlCredential
            The Password to connect to the Sql Instance with.
        
        .PARAMETER IgnoreLogBackup
            Whether the transaction logs should be ignored.
        
        .PARAMETER TrustDbBackupHistory
            Whether to trust the database backup history.
    
        .PARAMETER Silent
            Replaces user friendly yellow warnings with bloody red exceptions of doom!
            Use this if you want the function to throw terminating errors you want to catch.
        
        .PARAMETER Continue
            Continues restoring a database from a point in time

        .PARAMETER ContinuePoints
            The points to continue the restore from

        .PARAMETER DatabaseName
            Used when a restore is being continued with a name change
        
        .EXAMPLE
            Get-FilteredRestoreFile -Files $Files -SqlInstance $SqlInstance
    
            Filters out the backupfiles when compared to that sql instance's backup heades.
        
        .NOTES
            Additional information about the function.
    #>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]
        $Files,
        
        [Alias('SqlServer')]
        [parameter(Mandatory = $true)]


        [DbaInstanceParameter]
        $SqlInstance,
        
        [DateTime]
        $RestoreTime = (Get-Date).AddYears(1),
        
        [System.Management.Automation.PSCredential]
        $SqlCredential,
        
        [switch]
        $IgnoreLogBackup,
        
        [switch]
        $TrustDbBackupHistory,
        
        [switch]
        $Silent,

        [switch]
        $Continue,

        [object]
        $ContinuePoints,

        [string]
        $DatabaseName
    )
    begin {
        Write-Message -Level InternalComment -Message 'Starting'
        Write-Message -Level Debug -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
        
        $sqlInstanceParameterSplat = @{
            SqlInstance = $SqlInstance
        }
        if ($SqlCredential) { $sqlInstanceParameterSplat["SqlCredential"] = $SqlCredential }
        
        $allSqlBackupDetails = @()
        $outResults = @()
        $internalFiles = @()
    }
    process {
        foreach ($file in $files) {
            $internalFiles += $file
        }
    }
    end {
        if ($TrustDbBackupHistory) {
            Write-Message -Level Verbose -Message "Processing trusted backup history"
            
            $tmpInternalFiles = @()
            foreach ($row in $internalFiles) {
                if ($row.FullName.Count -gt 1) {
                    foreach ($filename in $row.FullName) {
                        $newIF = $row | Select-Object *
                        $NewIf.fullName = $filename.ToString()
                        $NewIf.BackupPath = $filename.ToString()
                        $tmpInternalFiles += $NewIf
                    }
                }
                else {
                    $tmpInternalFiles += $row
                }
            }
            $internalFiles = $tmpInternalFiles
            
            $allSqlBackupDetails += $internalFiles | Where-Object { $_.Type -eq 'Full' } | select-object *, @{ Name = "BackupTypeDescription"; Expression = { "Database" } }, @{ Name = "BackupType"; Expression = { "1" } }
            $allSqlBackupDetails += $internalFiles | Where-Object { $_.Type -eq 'Log' } | select-object *, @{ Name = "BackupTypeDescription"; Expression = { "Transaction Log" } }, @{ Name = "BackupType"; Expression = { "2" } }
            $allSqlBackupDetails += $internalFiles | Where-Object { $_.Type -eq 'Differential' } | select-object *, @{ Name = "BackupTypeDescription"; Expression = { "Database Differential" } }, @{ Name = "BackupType"; Expression = { "5" } }
        }
        else {
    		Write-Message -Level Verbose -Message "Read File headers (Read-DBABackupHeader)"		
			$AllSQLBackupdetails = $InternalFiles | ForEach-Object{if($_.fullname -ne $null){$_.Fullname}else{$_}} | Read-DBAbackupheader -sqlinstance $sqlinstance -SqlCredential $SqlCredential
        }

		Write-Message -Level Verbose -Message "$($AllSQLBackupdetails.count) Files to filter"
        $Databases = $AllSQLBackupdetails  | Group-Object -Property Servername, DatabaseName
        Write-Message -Level Verbose -Message "$(($Databases | Measure-Object).count) database to process"

        if ($Continue) {
            IF ($DatabaseName -ne '') {
                if (($Databases | Measure-Object).count -gt 1) {
                    Stop-Function -Message "More than 1 db restore for 1 db - exiting"
                    return
                } else {
                    $dbrec = $DatabaseName
                }
                
            }
            else {
                Write-Message -Level Verbose -Message "Continue set, so filtering to these databases :$($continuePoints.Database -join ',')"
                #$ignore = $Databases | Where-Object {$_.DatabaseName -notin ($continuePoints.Database)} | select-Object DatabaseName
                #Write-Verbose "Ignoring these: $($ignore -join ',')"
                $Databases = $Databases | Where-Object {(($_.Name -split ',')[1]).trim() -in ($continuePoints.Database)}
                
            }
        } 
		
		foreach ($Database in $Databases) {

            $Results = @()
            Write-Message -Level VeryVerbose -Message "Find Newest Full backup - $($_.DatabaseName)"

            $ServerName, $databaseName = $Database.Name.split(',').trim()

            Write-verbose "dbname = $databasename"
            $SQLBackupdetails = $AllSQLBackupdetails | Where-Object {$_.ServerName -eq $ServerName -and $_.DatabaseName -eq $DatabaseName.trim()}
            #If we're continuing a restore, then we aren't going to be needing a full backup....
            $TlogStartlsn = 0
            if (!($continue)) {
                $Fullbackup = $SQLBackupdetails | where-object {$_.BackupTypeDescription -eq 'Database' -and $_.BackupStartDate -lt $RestoreTime} | Sort-Object -Property BackupStartDate -descending | Select-Object -First 1
                $TlogStartlsn = $Fullbackup.FirstLSN
                if ($Fullbackup -eq $null) {
                    Stop-Function -Message "No Full backup found to anchor the restore" -Continue -Target $database
                    break
                }
                #This scans for striped full backups to build the results
                $Results += $SQLBackupdetails | where-object {$_.BackupTypeDescription -eq "Database" -and $_.FirstLSN -eq $FullBackup.FirstLSN}
            }
            else {
                Write-Message -Level VeryVerbose -Message "Continuing restore, setting fake fullbackup"
                if ($null -ne $dbrec) {
                     $dbfilter = $dbrec
                 }
                 else {
                     $dbfilter= $DatabaseName
                 }
                $Fullbackup = $ContinuePoints | Where-Object {$_.Database -eq $dbfilter}
                $TLogStartLsn = $Fullbackup.redo_start_lsn
                
            }    
           Write-Message -Level Verbose -Message "Got a Full backup, now to find diffs if they exist"
            
            #Get latest Differential Backup
            #If we're doing a continue and the last restore wasn't a full db we can't use a diff, so skip
            if ($null -eq $lastrestore -or $lastrestore -eq 'Database'  ) {
                $DiffbackupsLSN = ($SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Database Differential' -and $_.DatabaseBackupLSN -eq $Fullbackup.FirstLsn -and $_.BackupStartDate -lt $RestoreTime} | Sort-Object -Property BackupStartDate -descending | Select-Object -First 1).FirstLSN
                #Scan for striped differential backups
                $Diffbackups = $SqlBackupDetails | Where-Object {$_.BackupTypeDescription -eq 'Database Differential' -and $_.DatabaseBackupLSN -eq $Fullbackup.FirstLsn -and $_.FirstLSN -eq $DiffBackupsLSN}
                if ($null -ne $Diffbackups) {
                    Write-Message -Level Verbose -Message "we have at least one diff so look for tlogs after the last one"
                    #If we have a Diff backup, we only need T-log backups post that point
                    $TlogStartLSN = ($DiffBackups | select-object -Property FirstLSN -first 1).FirstLSN
                    $Results += $Diffbackups
                }
            }
            
            if ($fullBackup.RecoverModel -eq 'SIMPLE' -or $IgnoreLogBackup) {
                Write-Message -Level Verbose -Message "Database in simple mode or IgnoreLogBackup is true, skipping Transaction logs" -Target $database
            }
            else {
                write-verbose " frfID - $($Fullbackup.FirstRecoveryForkID)"
                write-verbose "tstart - $TlogStartLSN"
 
                Write-Message -Level Verbose -Message "Got a Full/Diff backups, now find all Tlogs needed"
                $AllTlogs = $SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log'} 
                $Filteredlogs = $SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log' -and $_.FirstRecoveryForkID -eq $Fullbackup.FirstRecoveryForkID -and $_.LastLSN -gt $TlogStartLSN -and $_.BackupStartDate -lt $RestoreTime}
                # -and $_.BackupStartDate -ge $LogStartDate
                $GroupedLogs = $FilteredLogs | Group-Object -Property LastLSN, FirstLSN
                $Tlogs = @()
                foreach ($LogGroup in $GroupedLogs) {
                    $Tlogs += $LogGroup.Group | Where-Object {$_.BackupSetGUID -eq ($LogGroup.Group | sort-Object -Property BackupStartDate -Descending | select-object -first 1).BackupSetGUID}
                }
                Write-Message -Level SomewhatVerbose -Message "Filtered $($allTlogs.count) log backups down to $($tLogs.count)" -Target $database
                $results += $tLogs
                #Catch the last Tlog that covers the restore time!
                $tLogfinal = $sqlBackupdetails | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' -and $_.BackupStartDate -gt $RestoreTime } | Sort-Object -Property LastLSN | Select-Object -First 1
                $results += $tLogfinal
                $tLogCount = ($results | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' }).count
                Write-Message -Level SomewhatVerbose -Message "$tLogCount Transaction Log backups found" -Target $database
            }
            
            [PSCustomObject]@{
                ID = $databaseName
                Values = $results
            }
        }
        
        Write-Message -Level InternalComment -Message 'Stopping'
    }
}
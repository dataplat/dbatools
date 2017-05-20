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
        $Silent
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
            Write-Message -Level Verbose -Message "Reading file headers using Read-DbaBackupHeader"
            $allSqlBackupDetails = $internalFiles | ForEach-Object {
                if ($_.fullname -ne $null) { $_.Fullname }
                else { $_ }
            } | Read-DbaBackupHeader @sqlInstanceParameterSplat
        }
        
        Write-Message -Level Verbose -Message "$($allSqlBackupDetails.count) Files to filter"
        $databases = $allSqlBackupDetails | Group-Object -Property Servername, DatabaseName
        Write-Message -Level Verbose -Message "$(($databases | Measure-Object).count) database to process"
        
        foreach ($database in $databases) {
            $fullBackup = $null
            $results = @()
            $serverName, $databaseName = $database.Name.split(',')
            Write-Message -Level VeryVerbose -Message "Find latest full backup for $serverName : $databaseName" -Target $database
            $sqlBackupdetails = $allSqlBackupDetails | Where-Object { $_.ServerName -eq $serverName -and $_.DatabaseName -eq $databaseName.trim() }
            $fullBackup = $sqlBackupdetails | where-object { $_.BackupTypeDescription -eq 'Database' -and $_.BackupStartDate -lt $RestoreTime } | Sort-Object -Property BackupStartDate -descending | Select-Object -First 1
            if (-not $fullBackup) {
                Stop-Function -Message "No Full backup found to anchor the restore for $serverName : $databaseName" -Continue -Target $database
            }
            #This scans for striped full backups to build the results
            $results += $sqlBackupdetails | where-object { $_.BackupTypeDescription -eq "Database" -and $_.BackupSetGUID -eq $fullBackup.BackupSetGUID }
            $logStartDate = $fullBackup.BackupStartDate
            
            Write-Message -Level Verbose -Message "Got a full backup, now to find diffs if they exist" -Target $database
            #Get latest Differential Backup
            $diffbackupsLSN = ($sqlBackupdetails | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' -and $_.DatabaseBackupLSN -eq $fullBackup.CheckpointLSN -and $_.BackupStartDate -gt $fullBackup.BackupStartDate -and $_.BackupStartDate -lt $RestoreTime } | Sort-Object -Property BackupStartDate -descending | Select-Object -First 1).FirstLSN
            $diffBackup = ($sqlBackupdetails | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' -and $_.DatabaseBackupLSN -eq $fullBackup.CheckpointLSN -and $_.BackupStartDate -gt $fullBackup.BackupStartDate -and $_.BackupStartDate -lt $RestoreTime } | Sort-Object -Property BackupStartDate -descending | Select-Object -First 1)
            
            #Scan for striped differential backups
            $diffbackups = $sqlBackupdetails | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' -and $_.FirstLSN -eq $diffbackupsLSN -and $_.BackupsetGUID -eq $diffBackup.BackupSetGUID }
            $tLogStartlsn = 0
            $tLogs = @()
            if ($null -ne $diffbackups) {
                Write-Message -Level Verbose -Message "We have at least one diff so look for tlogs after the last one" -Target $database
                #If we have a Diff backup, we only need T-log backups post that point
                $tLogStartlsn = ($diffbackups | select-object -Property FirstLSN -first 1).FirstLSN
                $results += $diffbackups
                $logStartDate = $diffBackup.BackupStartDate
            }
            
            if ($fullBackup.RecoverModel -eq 'SIMPLE' -or $IgnoreLogBackup) {
                Write-Message -Level Verbose -Message "Database in simple mode or IgnoreLogBackup is true, skipping Transaction logs" -Target $database
            }
            else {
                Write-Message -Level Verbose -Message "Got a Full/Diff backups, now find all Tlogs needed" -Target $database
                $allTlogs = $sqlBackupdetails | Where-Object BackupTypeDescription -eq 'Transaction Log'
                $filteredLogs = $sqlBackupdetails | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' -and $_.DatabaseBackupLSN -eq $fullBackup.CheckPointLSN -and $_.LastLSN -gt $tLogStartlsn -and $_.BackupStartDate -lt $RestoreTime -and $_.BackupStartDate -ge $logStartDate }
                $groupedLogs = $filteredLogs | Group-Object -Property LastLSN, FirstLSN
                foreach ($logGroup in $groupedLogs) {
                    $tLogs += $logGroup.Group | Where-Object { $_.BackupSetGUID -eq ($logGroup.Group | sort-Object -Property BackupStartDate -Descending | select-object -first 1).BackupSetGUID }
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
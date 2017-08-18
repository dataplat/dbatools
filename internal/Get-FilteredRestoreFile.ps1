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
        [switch]$TrustDbBackupHistory

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
            Write-Verbose "$FunctionName - Trusted backup history"

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
            }
            $InternalFiles = $tmpInternalFiles 

            $allsqlBackupDetails += $InternalFiles | Where-Object {$_.Type -eq 'Full'} | select-object *,  @{Name="BackupTypeDescription";Expression={"Database"}},  @{Name="BackupType";Expression={"1"}}
            $allsqlBackupDetails += $InternalFiles | Where-Object {$_.Type -eq 'Log'} | select-object *,  @{Name="BackupTypeDescription";Expression={"Transaction Log"}},  @{Name="BackupType";Expression={"2"}}
            $allsqlBackupDetails += $InternalFiles | Where-Object {$_.Type -eq 'Differential'} | select-object *,  @{Name="BackupTypeDescription";Expression={"Database Differential"}},  @{Name="BackupType";Expression={"5"}}

        }
        else
        {
    		Write-Verbose "$FunctionName - Read File headers (Read-DBABackupHeader)"		
			$AllSQLBackupdetails = $InternalFiles | ForEach{if($_.fullname -ne $null){$_.Fullname}else{$_}} | Read-DBAbackupheader -sqlserver $SQLSERVER -SqlCredential $SqlCredential
        }
		Write-Verbose "$FunctionName - $($AllSQLBackupdetails.count) Files to filter"
        $Databases = $AllSQLBackupdetails  | Group-Object -Property Servername, DatabaseName
        Write-Verbose "$FunctionName - $(($Databases | Measure-Object).count) database to process"
		
		foreach ($Database in $Databases){
            $Results = @()
            Write-Verbose "$FunctionName - Find Newest Full backup"
            $ServerName, $databaseName = $Database.Name.split(',')
            $SQLBackupdetails = $AllSQLBackupdetails | Where-Object {$_.ServerName -eq $ServerName -and $_.DatabaseName -eq $DatabaseName.trim()}
            $Fullbackup = $SQLBackupdetails | where-object {$_.BackupTypeDescription -eq 'Database' -and $_.BackupStartDate -lt $RestoreTime} | Sort-Object -Property BackupStartDate -descending | Select-Object -First 1
            if ($Fullbackup -eq $null)
            {
                Write-Warning "$FunctionName - No Full backup found to anchor the restore" 
                break
            }
            #This scans for striped full backups to build the results
            $Results += $SQLBackupdetails | where-object {$_.BackupTypeDescription -eq "Database" -and $_.FirstLSN -eq $FullBackup.FirstLSN}
            
            Write-Verbose "$FunctionName - Got a Full backup, now to find diffs if they exist"
            #Get latest Differential Backup
            $DiffbackupsLSN = ($SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Database Differential' -and $_.DatabaseBackupLSN -eq $Fullbackup.FirstLsn -and $_.BackupStartDate -lt $RestoreTime} | Sort-Object -Property BackupStartDate -descending | Select-Object -First 1).FirstLSN
            #Scan for striped differential backups
            $Diffbackups = $SqlBackupDetails | Where-Object {$_.BackupTypeDescription -eq 'Database Differential' -and $_.DatabaseBackupLSN -eq $Fullbackup.FirstLsn -and $_.FirstLSN -eq $DiffBackupsLSN}
            $TlogStartlsn = 0
            if ($null -ne $Diffbackups){
                Write-Verbose "$FunctionName - we have at least one diff so look for tlogs after the last one"
                #If we have a Diff backup, we only need T-log backups post that point
                $TlogStartLSN = ($DiffBackups | select-object -Property FirstLSN -first 1).FirstLSN
                $Results += $Diffbackups
            }
            
            if ($FullBackup.RecoverModel -eq 'SIMPLE' -or $IgnoreLogBackup)
            {
                Write-Verbose "$FunctionName - Database in simple mode or IgnoreLogBackup is true, skipping Transaction logs"
            }
            else
            {

                Write-Verbose "$FunctionName - Got a Full/Diff backups, now find all Tlogs needed"
                $AllTlogs = $SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log'} 
                $Tlogs = $SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log' -and $_.DatabaseBackupLSN -eq $Fullbackup.FirstLsn -and $_.LastLSN -gt $TlogStartLSN -and $_.BackupStartDate -lt $RestoreTime}
                Write-Verbose "$FunctionName - Filtered $($Alltlogs.count) down to $($Tlogs.count)"
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

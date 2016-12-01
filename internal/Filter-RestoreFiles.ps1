function Filter-RestoreFiles
{
<#
.SYNOPSIS
Internal Function to Filter a set of SQL Server backup files

.DESCRIPTION
Takes an array of FileSystem Objects and then filters them down by date to get a potential Restore set
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[System.Array]$Files,
        [parameter(Mandatory = $true)]
        [object]$SqlServer
	)
    $FunctionName = "Filter-RestoreFiles"
    $results = New-Object System.Data.DataSet
    Write-Verbose "$FunctionName - Starting"
    Write-Verbose "$FunctionName - Find Newest Full backup"
    $SQLBackupdetails  = $files | Read-DBAbackupheader -sqlserver $SQLSERVER 
    $Fullbackup = $SQLBackupdetails | where-object {$_.BackupType -eq 1} | Sort-Object -Property BackupStartDate -descending | Select-Object -First 1
    $results.tables.add($Fullbackup,"FullBackup")
    Write-Verbose "$FunctionName - Got a Full backup, now find all diffs"
    $Diffbackups = $SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Database Differential' -and $_.BackupStartDate -gt $Fullbackup.backupStartDate}
    $results.tables.Add($Diffbackups,"DiffBackups")
    if ($Diffbackups.count -gt 0){
        $TlogStartDate = ($DiffBackups | sort-object -property BackupStartDate -Descending | select-object -first 1).BackupStartDate
    }else{
       $TlogStartDate = $Fullbackup.BackupStartDate 
    }
    Write-Verbose "$FunctionName - Got a Full/Diff backups, now find all Tlogs needed"
    $Tlogs = $SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log' -and $_.backupStartDate -gt $TlogStartDate}
    $results.Tables.Add($Tlogs,"TranscationBackups")
    $results
}
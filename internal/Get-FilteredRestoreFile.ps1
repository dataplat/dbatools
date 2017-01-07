function Get-FilteredRestoreFile
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
        [object[]]$Files,
        [parameter(Mandatory = $true)]
        [object]$SqlServer,
        [DateTime]$RestoreTime = (Get-Date).addyears(1),
        [System.Management.Automation.PSCredential]$SqlCredential 

	)
    Begin
    {
        $FunctionName = "Filter-RestoreFile"
        Write-Verbose "$FunctionName - Starting"



        $Results = @()
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
        Write-Verbose "$FunctionName - Read File headers (Read-DBABackupHeader)"
        $SQLBackupdetails  = $InternalFiles | Select-Object -ExpandProperty FullName | Read-DBAbackupheader -sqlserver $SQLSERVER -SqlCredential:$SqlCredential
        Write-Verbose "$FunctionName - Find Newest Full backup"
        $Fullbackup = $SQLBackupdetails | where-object {$_.BackupType -eq "1" -and $_.BackupStartDate -lt $RestoreTime} | Sort-Object -Property BackupStartDate -descending | Select-Object -First 1
        if ($Fullbackup -eq $null)
        {
            Write-Error "$FunctionName - No Full backup found to anchor the restore"
        }

       $Results += $Fullbackup
        
        Write-Verbose "$FunctionName - Got a Full backup, now find all diffs"
        $Diffbackups = $SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Database Differential' -and $_.BackupStartDate -gt $Fullbackup.backupStartDate -and $_.BackupStartDate -lt $RestoreTime}
        $Results += $Diffbackups
        if ($Diffbackups.count -gt 0){
            Write-Verbose "$FunctionName - we have at least one diff so look for tlogs after the last one"
            $TlogStartDate = ($DiffBackups | sort-object -property BackupStartDate -Descending | select-object -first 1).BackupStartDate
        }else{
            Write-Verbose "$FunctionName - we have no diffs, so T-logs post full backup start "
            $TlogStartDate = $Fullbackup.BackupStartDate 
        }
        
        Write-Verbose "$FunctionName - Got a Full/Diff backups, now find all Tlogs needed"
        $Tlogs = $SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log' -and $_.backupStartDate -gt $TlogStartDate-and $_.BackupStartDate -lt $RestoreTime}
        $Results += $Tlogs
        #Catch the last Tlog that covers the restore time!
        $Tlogfinal = $SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log' -and $_.BackupStartDate -gt $RestoreTime} | Sort-Object -Property LastLSN  | select -First 1
        $Results +=$Tlogfinal
        Write-Verbose "$FunctionName - Returning Results to caller"
        $Results
    }
}
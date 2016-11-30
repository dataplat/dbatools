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
    $FunctionName = "Filter-RestoreFiles"`

    Write-Verbose "$FunctionName - Starting"
    [System.Array]$result
    Write-Verbose "$FunctionName - Find Newest Full backup"
    $tmp  = $files | where-object {$_.Extension -eq ".bak"} | Read-DBAbackupheader -sqlserver $SQLSERVER 
    Write-Verbose "$($tmp.count) objects"
    $results = $tmp | where-object {$_.BackupType -eq 1} | Sort-Object -Property backupStartDate | Select-Object -First 1
    Write-Verbose "$($results.count) objects"
    $results
}
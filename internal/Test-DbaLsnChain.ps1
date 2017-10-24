function Test-DbaLsnChain
{
<#
.SYNOPSIS 
Checks that a filtered array from Get-FilteredRestore contains a restorabel chain of LSNs

.DESCRIPTION
Finds the anchoring Full backup (or multiple if it's a striped set).
Then filters to ensure that all the backups are from that anchor point (LastLSN) and that they're all on the same RecoveryForkID
Then checks that we have either enough Diffs and T-log backups to get to where we want to go. And checks that there is no break between
LastLSN and FirstLSN in sequential files
	
.PARAMETER FilteredRestoreFiles
This is just an object consisting of the output from Read-DbaBackupHeader. Normally this will have been filtered down to a restorable chain 
before arriving here. (ie; only 1 anchoring Full backup)
	
.NOTES 
Author: Stuart Moore (@napalmgram), stuart-moore.com
Tags:
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Test-DbaLsnChain -FilteredRestoreFiles $FilteredFiles

Checks that the Restore chain in $FilteredFiles is complete and can be fully restored

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$FilteredRestoreFiles,
        [switch]$Continue
	)

    #Need to anchor  with full backup:
    $FunctionName =(Get-PSCallstack)[0].Command
    if ($continue)
    {
        return $true
    }
    Write-Verbose "$FunctionName - Testing LSN Chain"
    $FullDBAnchor = $FilteredRestoreFiles | Where-Object {$_.BackupTypeDescription -eq 'Database'}
    if (($FullDBAnchor | Group-Object -Property FirstLSN | Measure-Object).count -ne 1)
    {
        $cnt = ($FullDBAnchor | Group-Object -Property FirstLSN | Measure-Object).count
        Foreach ($tFile in $FullDBAnchor){write-verbose "$($tfile.FirstLsn) - $($tfile.BackupTypeDescription)"}
        Write-Verbose "$FunctionName - db count = $cnt"
        Write-Warning "$FunctionName - More than 1 full backup from a different LSN, or less than 1, neither supported"

        return $false
        break;
    }

    #Via LSN chain:
    $CheckPointLSN = ($FullDBAnchor | Select-Object -First 1).CheckPointLSN
    $FullDBLastLSN = ($FullDBAnchor | Select-Object -First 1).LastLSN 
    $BackupWrongLSN = $FilteredRestoreFiles | Where-Object {$_.DatabaseBackupLSN -ne $CheckPointLSN}
    #Should be 0 in there, if not, lets check that they're from during the full backup
    if ($BackupWrongLSN.count -gt 0 ) 
    {
        if (($BackupWrongLSN | Where-Object {$_.LastLSN -lt $FullDBLastLSN}).count -gt 0)
        {
            Write-Warning "$FunctionName - We have non matching LSNs - not supported"
            return $false
            break;
        }
    }
    $DiffAnchor = $FilteredRestoreFiles | Where-Object {$_.BackupTypeDescription -eq 'Database Differential'}
    #Check for no more than a single Differential backup
    if (($DiffAnchor.FirstLSN | Select-Object -unique | Measure-Object).count -gt 1)
    {
        Write-Warning "$FunctionName - More than 1 differential backup, not  supported"
        return $false
        break;        
    } 
    elseif (($DiffAnchor | Measure-Object).count -eq 1)
    {
        $TlogAnchor = $DiffAnchor
    } 
    else 
    {
        $TlogAnchor = $FullDBAnchor
    }


    #Check T-log LSNs form a chain.
    $TranLogBackups = $FilteredRestoreFiles | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log' -and $_.DatabaseBackupLSN -eq $FullDBAnchor.CheckPointLSN} | Sort-Object -Property LastLSN, FirstLsn
    for ($i=0; $i -lt ($TranLogBackups.count)-1)
    {
        if ($i -eq 0)
        {
            if ($TranLogBackups[$i].FirstLSN -ge $TlogAnchor.LastLSN)
            {
                Write-Warning "$FunctionName - Break in LSN Chain between $($TlogAnchor.BackupPath) and $($TranLogBackups[($i)].BackupPath) "
                return $false
                break
            }
        }else {
            if ($TranLogBackups[($i-1)].LastLsn -ne $TranLogBackups[($i)].FirstLSN -and ($TranLogBackups[($i)] -ne $TranLogBackups[($i-1)]))
            {
                Write-Warning "$FunctionName - Break in transaction log between $($TranLogBackups[($i-1)].BackupPath) and $($TranLogBackups[($i)].BackupPath) "
                return $false
                break
            }
        }
        $i++

    }  
    Write-Verbose "$FunctionName - Passed LSN Chain checks" 
    return $true
}


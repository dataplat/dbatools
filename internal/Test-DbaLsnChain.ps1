function Test-DbaLsnChain
{
<#
.SYNOPSIS 
Checks that a filtered array from Get-FilteredRestore contains a restorabel chain of LSNs

.DESCRIPTION
	
.PARAMETER FilterdRestoreFiles
	
.PARAMETER RestoreTime
Returns fewer columns for an easy overview
	

.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.EXAMPLE
Test-DbaLsnChain -FilteredRestoreFiles $FilteredFiles

Checks that the Restore chain in $FilteredFiles is complete and can be fully restored

.EXAMPLE
Test-DbaLsnChain -FilteredRestoreFiles $FilteredFiles -RestoreTime '23/12/2016 06:55'

Checks that the Restore chain in $FilteredFiles is complete and can be fully restored to the Point In Time '23/12/2016 06:55'
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true)]
        [object[]]$FilteredRestoreFiles,
        [DateTime]$RestoreTime = (Get-Date).addyears(1)
	)

    #Need to anchor  with full backup:
    $FunctionName = "Test-DbaLsnChain"
    $FullDBAnchor = $FilteredRestoreFiles | Where-Object {$_.BackupTypeDescription -eq 'Database'}
    if (($FullDBAnchor | Measure-Object).count -ne 1)
    {
        Write-Error "$FunctionName - More than 1 full backup, or less than 1, neither supported"
        return $false
        break;
    }
    #Check all the backups relate to the full backup
    #Via RecoveryForkID:
    if (($FilteredRestoreFiles | Where-Object {$_.RecoveryForkID -ne $FullDBAnchor.RecoveryForkID}).count -gt 0)
    {
        Write-Error "$FunctionName - Multiple RecoveryForkIDs found, not supported"
        return $false
        break
    }
    #Via LSN chain:
    $BackupWrongLSN = $FilteredRestoreFiles | Where-Object {$_.DatabaseBackupLSN -ne $FullDBAnchor.CheckPointLSN}
    #Should be 0 in there, if not, lets check that they're from during the full backup
    if ($BackupWrongLSN.count -gt 0 ) 
    {
        if (($BackupWrongLSN | Where-Object {$_.LastLSN -lt $FullDBAnchor.LastSN}).count -gt 0)
        {
            Write-Error "$FunctionName - We have non matching LSNs - not supported"
            return $false
            break;
        }
    }
    $DiffAnchor = $FilteredRestoreFiles | Where-Object {$_.BackupTypeDescription -eq 'Database Differential'}
    #Check for no more than a single Differential backup
    if (($DiffAnchor | Measure-Object).count -gt 1)
    {
        Write-Error "$FunctionName - More than 1 differential backup, not  supported"
        return $false
        break;        
    } 
    elseif (($DiffAnchor | Measure-Object).count -gt 1)
    {
        $TlogAnchor = $DiffAnchor
    } 
    else 
    {
        $TlogAnchor = $FullDBAnchor
    }


    #Check T-log LSNs form a chain.
    $TranLogBackups = $FilteredRestoreFiles | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log' -and $_.DatabaseBackupLSN -eq $FullDBAnchor.CheckPointLSN} | Sort-Object -Propert LastLSN
    for ($i=0; $i -lt ($TranLogBackups.count)-1)
    {
        if ($i -eq 0)
        {
            if ($TranLogBackups[$i].FirstLSN -gt $TlogAnchor.LastLSN)
            {
                Write-Error "$FunctionName - Break in LSN Chain between $($TlogAnchor.BackupPath) and $($TranLogBackups[($i)].BackupPath) "
                return $false
                break
            }
        }else {
            if ($TranLogBackups[($i-1)].LastLsn -ne $TranLogBackups[($i)].FirstLSN)
            {
                Write-Error "$FunctionName - Break in transaction log between $($TranLogBackups[($i-1)].BackupPath) and $($TranLogBackups[($i)].BackupPath) "
                return $false
                break
            }
        }
        $i++

    }    
    return $true
}


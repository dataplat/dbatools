function Test-DbaLsnChain {
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
        dbatools PowerShell module (https://dbatools.io)
       Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        Test-DbaLsnChain -FilteredRestoreFiles $FilteredFiles

        Checks that the Restore chain in $FilteredFiles is complete and can be fully restored

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$FilteredRestoreFiles,
        [switch]$Continue,
        [switch]$EnableException
    )


    begin {
        #Need to anchor  with full backup:
        $TestHistory = @()
    }
    process {
        foreach ($bh in $FilteredRestoreFiles) {
            $TestHistory += $bh
        }
    }
    end {
        if ($continue) {
            return $true
        }
        Write-Message -Level Verbose -Message "Testing LSN Chain"
        if ($null -eq $TestHistory[0].BackupTypeDescription) {
            $TypeName = 'Type'
        } else {
            $TypeName = "BackupTypeDescription"
        }
        Write-Message -Level VeryVerbose -Message "Testing LSN Chain - Type $typename"
        $FullDBAnchor = $TestHistory | Where-Object { $_.$TypeName -in ('Database', 'Full') }

        if (($FullDBAnchor | Group-Object -Property FirstLSN | Measure-Object).Count -ne 1) {
            $cnt = ($FullDBAnchor | Group-Object -Property FirstLSN | Measure-Object).Count
            foreach ($tFile in $FullDBAnchor) {
                Write-Message -Level Debug -Message "$($tfile.FirstLsn) - $($tfile.TypeName)"
            }
            Write-Message -Level Verbose -Message "db count = $cnt"
            Write-Message -Level Warning -Message "More than 1 full backup from a different LSN, or less than 1, neither supported"

            return $false
            break;
        }

        #Via LSN chain:
        [BigInt]$CheckPointLSN = ($FullDBAnchor | Select-Object -First 1).CheckPointLSN.ToString()
        [BigInt]$FullDBLastLSN = ($FullDBAnchor | Select-Object -First 1).LastLSN.ToString()
        $BackupWrongLSN = $FilteredRestoreFiles | Where-Object { $_.DatabaseBackupLSN -ne $CheckPointLSN }
        #Should be 0 in there, if not, lets check that they're from during the full backup
        if ($BackupWrongLSN.count -gt 0 ) {
            if (($BackupWrongLSN | Where-Object { [BigInt]$_.LastLSN.ToString() -lt $FullDBLastLSN }).count -gt 0) {
                Write-Message -Level Warning -Message "We have non matching LSNs - not supported"
                return $false
                break;
            }
        }
        $DiffAnchor = $TestHistory | Where-Object { $_.$TypeName -in ('Database Differential', 'Differential') }
        #Check for no more than a single Differential backup
        if (($DiffAnchor.FirstLSN | Select-Object -unique | Measure-Object).count -gt 1) {
            Write-Message -Level Warning -Message "More than 1 differential backup, not supported"
            return $false
            break;
        } elseif (($DiffAnchor | Measure-Object).Count -eq 1) {
            Write-Message -Level VeryVerbose -Message "Found a diff file, setting Log Anchor"
            $TlogAnchor = $DiffAnchor
        } else {
            $TlogAnchor = $FullDBAnchor
        }


        #Check T-log LSNs form a chain.
        $TranLogBackups = $TestHistory | Where-Object { $_.$TypeName -in ('Transaction Log', 'Log') -and $_.DatabaseBackupLSN -eq $FullDBAnchor.CheckPointLSN } | Sort-Object -Property LastLSN, FirstLsn
        for ($i = 0; $i -lt ($TranLogBackups.count)) {
            Write-Message -Level Debug -Message "looping t logs"
            if ($i -eq 0) {
                if ($TranLogBackups[$i].FirstLSN -gt $TlogAnchor.LastLSN) {
                    Write-Message -Level Warning -Message "Break in LSN Chain between $($TlogAnchor.FullName) and $($TranLogBackups[($i)].FullName) "
                    Write-Message -Level Verbose -Message "Anchor $($TlogAnchor.LastLSN) - FirstLSN $($TranLogBackups[$i].FirstLSN)"
                    return $false
                    break
                }
            } else {
                if ($TranLogBackups[($i - 1)].LastLsn -ne $TranLogBackups[($i)].FirstLSN -and ($TranLogBackups[($i)] -ne $TranLogBackups[($i - 1)])) {
                    Write-Message -Level Warning -Message "Break in transaction log between $($TranLogBackups[($i-1)].FullName) and $($TranLogBackups[($i)].FullName) "
                    return $false
                    break
                }
            }
            $i++

        }
        Write-Message -Level VeryVerbose -Message "Passed LSN Chain checks"
        return $true
    }
}
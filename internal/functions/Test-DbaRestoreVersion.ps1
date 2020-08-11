function Test-DbaRestoreVersion {
    <#
    .SYNOPSIS
        Checks that the restore files are from a version of SQL Server that can be restored on the target version

    .DESCRIPTION
        Finds the anchoring Full backup (or multiple if it's a striped set).
        Then filters to ensure that all the backups are from that anchor point (LastLSN) and that they're all on the same RecoveryForkID
        Then checks that we have either enough Diffs and T-log backups to get to where we want to go. And checks that there is no break between
        LastLSN and FirstLSN in sequential files

    .PARAMETER FilteredRestoreFiles
        This is just an object consisting of the output from Read-DbaBackupHeader. Normally this will have been filtered down to a restorable chain
        before arriving here. (ie; only 1 anchoring Full backup)

    .PARAMETER SqlInstance
        Sql Server Instance against which the restore is going to be performed

    .PARAMETER SqlCredential
        Credential for connecting to SqlInstance

    .PARAMETER SystemDatabaseRestore
        Switch when restoring system databases

    .NOTES
        Author: Stuart Moore (@napalmgram), stuart-moore.com
        Tags:
        dbatools PowerShell module (https://dbatools.io)
       Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        Test-DbaRestoreVersion -FilteredRestoreFiles $FilteredFiles -SqlInstance server1\instance1

        Checks that the Restore chain in $FilteredFiles is compatible with the SQL Server version of server1\instance1

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [object]$SqlInstance,
        [parameter(Mandatory)]
        [object[]]$FilteredRestoreFiles,
        [PSCredential]$SqlCredential,
        [switch]$SystemDatabaseRestore
    )
    $RestoreVersion = ($FilteredRestoreFiles.SoftwareVersionMajor | Measure-Object -average).average
    Write-Message -Level Verbose -Message "RestoreVersion is $RestoreVersion"
    #Test to make sure we don't have an upgrade mid backup chain, there's a reason I'm paranoid..
    if ([int]$RestoreVersion -ne $RestoreVersion) {
        Write-Message -Level Warning -Message "Version number change during backups - $RestoreVersion"
        return $false
        break
    }
    #Can't restore backwards
    try {
        if ($SqlInstance -isnot [Microsoft.SqlServer.Management.Smo.SqlSmoObject]) {
            $Newconnection = $true
            $Server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } else {
            $server = $SqlInstance
        }
    } catch {
        Write-Message -Level Warning -Message "Cannot connect to $SqlInstance"
        break
    }

    if ($SystemDatabaseRestore) {
        if ($RestoreVersion -ne $Server.VersionMajor) {
            Write-Message -Level Warning -Message "For System Database restore versions must match)"
            return $false
            break
        }
    } else {
        if ($RestoreVersion -gt $Server.VersionMajor) {
            Write-Message -Level Warning -Message "Backups are from a newer version of SQL Server than $($Server.Name)"
            return $false
            break
        }

        if (($Server.VersionMajor -gt 10 -and $RestoreVersion -lt 9)  ) {
            Write-Message -Level Warning -Message "This version - $RestoreVersion - too old to restore on to $($Server.Name)"
            return $false
            break
        }
    }
    if ($Newconnection) {
        $server.ConnectionContext.Disconnect()
    }
    return $True
}
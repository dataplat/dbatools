function Test-DbaRestoreVersion
{
<#
.SYNOPSIS 
Checks that the restore files are from a version of SQL Server that can be restored on the target version

.DESCRIPTION
Finds the anchoring Full backup (or multiple if it's a striped set).
Then filters to ensure that all the backups are from that anchor point (LastLSN) and that they're all on the same RecoveryForkID
Then checks that we have either enough Diffs and T-log backups to get to where we want to go. And checks that there is no break between
LastLSN and FirstLSN in sequential files
	
.PARAMETER FilterdRestoreFiles
This is just an object consisting of the output from Read-DbaBackupHeader. Normally this will have been filtered down to a restorable chain 
before arriving here. (ie; only 1 anchoring Full backup)

.PARAMETER SqlInstance
Sql Server Instance against which the restore is going to be performed

.PARAMETER SqlCredential
Credential for connectin to SqlInstance

.PARAMETER SystemDatabaseRestore
Switch when restoring system databases

.NOTES 
Original Author: Stuart Moore (@napalmgram), stuart-moore.com

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.EXAMPLE
Test-DbaRestoreVersion -FilteredRestoreFiles $FilteredFiles -SqlInstance server1\instance1 

Checks that the Restore chain in $FilteredFiles is compatiable with the SQL Server version of server1\instance1 

#>
	[CmdletBinding()]
	Param (
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
		[object]$SqlInstance,
        [parameter(Mandatory = $true)]
        [object[]]$FilteredRestoreFiles,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [switch]$SystemDatabaseRestore
        
	)
    $FunctionName =(Get-PSCallstack)[0].Command
    $RestoreVersion = ($FilteredRestoreFiles.SoftwareVersionMajor | Measure-Object -average).average
    Write-Verbose "$FunctionName - RestoreVersion is $RestoreVersion"
    #Test to make sure we don't have an upgrade mid backup chain, there's a reason I'm paranoid..
    if ([int]$RestoreVersion -ne $RestoreVersion)
    {
        Write-Warning "$FunctionName - Version number change during backups - $RestoreVersion"
        return $false
        break
    }
    #Can't restore backwards
    try 
    {
        if ($SqlInstance -isnot [Microsoft.SqlServer.Management.Smo.SqlSmoObject])
        {
            $Newconnection  = $true
            $Server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential	
        }
        else
        {
            $server = $SqlInstance
        }
    }
    catch 
    {
        Write-Warning "$FunctionName - Cannot connect to $SqlInstance" 
        break
    } 

    if ($SystemDatabaseRestore)
    {
        if ($RestoreVersion -ne $Server.VersionMajor)
        {
            Write-Warning "$FunctionName - For System Database restore versions must match)"
            return $false
            break   
        }
    }
    else 
    {
        if ($RestoreVersion -gt $Server.VersionMajor)
        {
            Write-Warning "$FunctionName - Backups are from a newer version of SQL Server than $($Server.Name)"
            return $false
            break   
        }

        if (($Server.VersionMajor -gt 10 -and $RestoreVersion -lt 9)  )
        {
            Write-Warning "$FunctionName - This version - $RestoreVersion - too old to restore on to $($Server.Name)"
            return $false
            break 
        }
    }
    if ($Newconnection)
    {
        Write-Verbose "$FunctionName - Closing smo connection"
        $server.ConnectionContext.Disconnect()
    }
    return $True
}


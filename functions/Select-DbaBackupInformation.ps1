function Select-DbaBackupInformation{
<#
    .SYNOPSIS 
    Select a subset of backups from a dbatools backup history object

    .DESCRIPTION
    Set-DbaAgentJob updates a job in the SQL Server Agent with parameters supplied.

    .PARAMETER BackupHistory
    A dbatools.BackupHistory object containing backup history records

    .PARAMETER RestoreTime
    The point in time you want to restore to

    .PARAMETER IgnoreLogs
    
    .PARAMETER IgnoreDiffs

    .PARAMETER DatabaseName
    

    .PARAMETER ServerName
    
    

    .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
            
    .NOTES 
    Author:Stuart Moore (@napalmgram stuart-moore.com )
    Tags: Backup
        
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Set-DbaAgentJob

    .EXAMPLE   
    $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
    $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1)

    .EXAMPLE
    $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
    $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1) -DatabaseName ProdFinance

    .EXAMPLE
    $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
    $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1) -IgnoreLogs

    .EXAMPLE
    $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
    $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1) -IgnoreDiffs

    
    Changes a job with the name "Job1" on multiple servers to have another description using pipe line

    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$BackupHistory,
        [DateTime]$RestoreTime = (get-date).addmonths(1),
        [switch]$IgnoreLogs,
        [switch]$IgnoreDiffs,
        [string[]]$DatabaseName,
        [string[]]$ServerName,
        [switch]$EnableException
    )
    begin{
        $InternalHistory = @()
    }
    process{
        foreach ($h in $backupHistory){
            $internalHistory += $h
        }

    }
    
    end{
        $InternalHistory = $BackupHistory
        <#       foreach ($History in $BackupHistory){
                   $InternalHistory += $History
               }
          #>     
               if (Test-Bound -ParameterName DatabaseName){
                   $InternalHistory = $InternalHistory | Where-Object {$_.Database -in $DatabaseName}
               }
               if (Test-Bound -ParameterName ServerName){
                   $InternalHistory = $InternalHistory | Where-Object {$_.InstanceName -in $servername}
               }
       
               #$InternalHistory
             #  ForEach ($Database in ($InternalHistory.Database | select-Object -Unique)) {
                   $DatabaseHistory = $InternalHistory
                   # | Where-Object {$_.Database -eq $Database}

                  
                   $dbHistory = @()
                   #Find the Last Full Backup before RestoreTime
                   $dbHistory += $Full =  $DatabaseHistory | Where-Object {$_.Type -in ('Full','Database') -and $_.Start -le $RestoreTime} | Sort-Object -Property LastLsn -Descending | Select-Object -First 1
                   #"Full"
                   #$Full
                   #Find the Last diff between Full and RestoreTime
       
                   $dbHistory += $DatabaseHistory | Where-Object {$_.Type -in ('Differential','Database Differential')  -and $_.Start -le $RestoreTime -and $_.DatabaseBackupLSN -eq $Full.CheckpointLSN} | Sort-Object -Property LastLsn -Descending | Select-Object -First 1
                   #$dbHistory
                   #Get All t-logs up to restore time
                   $LogBaseLsn = ($dbHistory | Sort-Object -Property LastLsn -Descending | select-object -First 1).lastLsn
                   $FilteredLogs = $DatabaseHistory | Where-Object {$_.Type -in ('Log','Transaction Log') -and $_.Start -le $RestoreTime -and $_.DatabaseBackupLSN -eq $Full.CheckpointLSN -and $_.LastLSN -ge $LogBaseLsn} | Sort-Object -Property LastLsn
                   $GroupedLogs = $FilteredLogs | Group-Object -Property LastLSN, FirstLSN
                   ForEach ($Group in $GroupedLogs){
                       $dbhistory += $DatabaseHistory | Where-Object {$_.BackupSetID -eq $Group.group[0].BackupSetID}
                   }
                  # $dbHistory
                   # Get Last T-log
                   $dbHistory += $DatabaseHistory | Where-Object {$_.Type -in ('Log','Transaction Log') -and $_.End -ge $RestoreTime -and $_.DatabaseBackupLSN -eq $Full.CheckpointLSN} | Sort-Object -Property LastLsn -Descending | Select-Object -First 1
                $dbHistory
             #  }
    }
}
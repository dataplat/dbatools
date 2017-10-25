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
        [Alias("ServerInstance", "SqlServer")]
        [BackupHistory[]]$BackupHistory,
        [DateTime]$RestoreTime,
        [switch]$IgnoreLogs,
        [switch]$IgnoreDiffs,
        [string[]]$DatabaseName,
        [string[]]$ServerName,
        [switch]$EnableException
    )
    begin{}
    process{
        $OutputHistory = @()
        foreach ($History in $BackupHistory){
            if (Test-Bound -ParameterName $DatabaseName){
                $History = $History | Where-Object {$_.Database -in $DatabaseName}
            }
            if (Test-Bound -ParameterName $ServerName){
                $History = $History | Where-Object {$_.InstanceName -in $servername}
            }
            if (Test-Bound -ParameterName $RestoreTime){
                $History = $History | Where-Object {$_.InstanceName -in $servername}
            }
        }
    }
    end{}
}
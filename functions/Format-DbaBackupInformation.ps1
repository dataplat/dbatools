Function Format-DbaBackupInformation{
    <#
    .SYNOPSIS
        Transforms the data in a dbatools backuphistory object for a restore
    
    .DESCRIPTION
       Performs various mapping on Backup History, ready restoring
       Options include changing restore paths, backup paths, database name and many others
    
    .PARAMETER BackupHistory

    .PARAMETER ReplaceDatabasName
        If a single value is provided, this will be replaced do all occurences a database name
        If a Hashtable is passed in, each database name mention will be replaced as specified. If a database's name does not apper it will not be replace
        DatabaseName will also be replaced where it  occurs in the file paths of data and log files.
        Please note, that this won't change the Logical Names of datafiles, that has to be done with a seperate Alter DB call
    
    .PARAMETER DatabaseNamePrefix
        This string will be prefixed to all restored database's name 
        
    .PARAMETER DataFileDirectory
        This will move ALL restored files to this location during the restore

    .PARAMETER LogFileDirectory
        This will move all log files to this location. 
    
    .PARAMETER FileNamePrefix
        This string will  be prefixed to all restored files (Data and Log)

    .PARAMETER BackupFolder
        Use this to rebase where your backups are stored. 

    .EXAMPLE
        $BackupHistory | Format-DbaBackupInformation -ReplaceDatabaseName NewDb

    .EXAMPLE
        $BackupHistory | Format-DbaBackupInformation -ReplaceDatabaseName @{'OldB'='NewDb';'ProdHr'='DevPr'}   
    
    .EXAMPLE
        $BackupHistory | Format-DbaBackupInformation -DataFileDirectory 'D:\DataFiles\' -LogFileDirectory 'E:\LogFiles\
    #>
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$BackupHistory,
        [object[]]$ReplaceDatabaseName,
        [string]$DataFileDirectory,
        [string]$LogFileDirectory,
        [string]$DatabaseNamePrefix,
        [string]$DatabaseFilePrefix,
        [string]$DatabaseFileSuffix,
        [string]$BackupFolder
    )
    Begin{
        if (Test-Bound -ParameterName ReplaceDatabaseName){
            if ($ReplaceDatabaseName -is [string]){
                $ReplaceDatabaseNameType = 'single'
            }
            elseif ($ReplaceDatabaseName -is [hash]) {
                $ReplaceDatabaseNameType='multi'
            }
        }
    }


    Process{
        ForEach ($history in $BackupHistory){
            $history | Add-Member -Name 'OriginalDatabase' -Type NoteProperty -Value $_.database
            $history | Add-Member -Name 'OriginalFileList' -Type NoteProperty -Value $_.OriginalFileList
            $history | Add-Member -Name 'OriginalFullName' -Type NoteProperty -Value $_.FullName
            if ($ReplaceDatabaseNameType = 'single'){
                $ReplaceDatabaseNameInner = $ReplaceDatabaseName
            }elseif ($ReplaceDatabaseNameType ='multi'){
                $ReplaceDatabaseNameInner = $ReplaceDatabaseName[$history.Database]
            }
            $history.Database -replace "$($_.Database)", $ReplaceDatabaseName
            $history.FileList | ForEach-Object {
                $_.PhysicalName -Replace "$($_.Database)", $ReplaceDatabaseName
                $Pname = [System.Io.FileInfo]$_.PhysicalName
                $RestoreDir = $Pname.DirectoryName
                if ($_.Type -eq 'D'){
                    if ($null -ne $DataFileDirectory){
                        $RestoreDir = $DataFileDirectory
                    }
                }elseif ($_.Type -eq 'L'){
                    if ($null -ne $LogFileDirectory){
                        $RestoreDir = $LogFileDirectory
                    }
                    elseif ($null -ne $DataFileDirectory){
                        $RestoreDir = $DataFileDirectory
                    }
                }
                
                $_.PhysicalName = $RestoreDir+"\"+$DatabaseFilePrefix+$Pname.BaseName+$DatabaseFileSuffix+$pname.extension
            }
            if ($null -ne $BackupFolder){
                $history.FullName | ForEach-Object{
                    $file = [System.IO.FileInfo]$_
                    $_ = $BackupFolder+"\"+$file.BaseName+$file.Extension
                }
            }
            
        }
    }

    End{
        return $BackupHistory
    }
}
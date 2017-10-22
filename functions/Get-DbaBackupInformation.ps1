function Get-DbaBackupInformation {
    <#
    .SYNOPSIS
        Restores a SQL Server Database from a set of backupfiles
    
    .DESCRIPTION
        Upon bein passed a list of potential backups files this command will scan the files, select those that contain SQL Server
        backup sets. It will then filter those files down to a set 

        The function defaults to working on a remote instance. This means that all paths passed in must be relative to the remote instance.
        XpDirTree will be used to perform the file scans
                
        Various means can be used to pass in a list of files to be considered. The default is to non recursively scan the folder
        passed in.
    
    .PARAMETER Path
        Path to SQL Server backup files.
        
        Paths passed in as strings will be scanned using the desired method, default is a non recursive folder scan
        Accepts multiple paths seperated by ','
        
        Or it can consist of FileInfo objects, such as the output of Get-ChildItem or Get-Item. This allows you to work with
        your own filestructures as needed
    
    .PARAMETER SqlInstance
        The SQL Server instance to be used to read the headers of the backup files
    
    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.
    
    .PARAMETER DatabaseName
        An arrary of Database Names to filter by. If empty all databases are returned.

    .PARAMETER SourceInstance
        If provided only backup originating from this destination will be returned. This SQL instance will not be connected to or involved in this work
    .PARAMETER XpDirTree
        Switch that indicated file scanning should be performed by the SQL Server instance using xp_dirtree
        This will scan recursively from the passed in path
        You must have sysadmin role membership on the instance for this to work.
    
    .PARAMETER XpNoRecurse
        If specified, prevents the XpDirTree process from recursing (its default behaviour)

	.PARAMETER DirectoryRecurse
		If specified the specified directory will be recursed into
	
	.PARAMETER EnableException
        Replaces user friendly yellow warnings with bloody red exceptions of doom!
        Use this if you want the function to throw terminating errors you want to catch.
    
	.PARAMETER Confirm
        Prompts to confirm certain actions
    
    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command
    
    .EXAMPLE
        Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups
        
        Scans all the backup files in \\server2\backups, filters them and restores the database to server1\instance1
    
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$Path,
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential,
        [string[]]$DatabaseName,
        [string[]]$SourceInstance,
        [Switch]$XpDirTree,
        [switch]$Recurse,
        [switch]$EnableException
      
    )
    begin {
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Debug -Message "Parameters bound: $($PSBoundParameters.Keys -join ", ")"

        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        $Files = @()
        if ($XpDirTree -eq $true){
            ForEach ($f in $path) {
                $Files += Get-XpDirTreeRestoreFile -Path $f -SqlInstance $SqlInstance -SqlCredential $SqlCredential
            }
        } 
        else {
            ForEach ($f in $path) {
                $Files += Get-ChildItem -Path $f -file -Recurse:$recurse
            }
        }
        
        $FileDetails = $Files | Read-DbaBackupHeader -SqlInstance $SqlInstance -SqlCredential $sqlcredential
        if (Was-Bound 'SourceInstance') {
            $FileDetails = $FileDetails | Where-Object {$_.ServerName -in $SourceInstance}
        }

        if (Was-Bound 'DatabaseName') {
            $FileDetails = $FileDetails | Where-Object {$_.DatabaseName -in $DatabaseName}
        }

        $groupdetails = $FileDetails | group-object -Property BackupSetGUID
        $groupResults = @()
        Foreach ($Group in $GroupDetails){
            $historyObject = New-Object Sqlcollaborative.Dbatools.Database.BackupHistory
            $historyObject.ComputerName = $group.group[0].MachineName
            $historyObject.InstanceName = $group.group[0].ServiceName
            $historyObject.SqlInstance = $group.group[0].ServerName
            $historyObject.Database = $group.Group[0].DatabaseName
            $historyObject.UserName = $group.Group[0].UserName
            $historyObject.Start = [DateTime]$group.Group[0].BackupStartDate
            $historyObject.End = [DateTime]$group.Group[0].BackupFinishDate
            $historyObject.Duration = ([DateTime]$group.Group[0].BackupFinishDate - [DateTime]$group.Group[0].BackupStartDate).Seconds
            $historyObject.Path = $Group.Group.BackupPath
            $historyObject.TotalSize = (Measure-Object $Group.Group.BackupSizeMB -sum).sum
            $historyObject.Type = $group.Group[0].BackupTypeDescription
            $historyObject.BackupSetId = $group[0].BackupSetGUID
            $historyObject.DeviceType = 'Disk'
            $historyObject.FullName = $Group.Group.BackupPath
            $historyObject.FileList = $Group.Group[0].FileList
            $historyObject.Position = $group.Group[0].Position
            $historyObject.FirstLsn = $group.Group[0].FirstLSN
            $historyObject.DatabaseBackupLsn = $group.Group[0].DatabaseBackupLSN
            $historyObject.CheckpointLsn = $group.Group[0].CheckpointLSN
            $historyObject.LastLsn = $group.Group[0].LastLsn
            $historyObject.SoftwareVersionMajor = $group.Group[0].SoftwareVersionMajor
            $groupResults += $historyObject
        }
        $groupResults | Sort-Object -Property End -Descending
    }

    
}
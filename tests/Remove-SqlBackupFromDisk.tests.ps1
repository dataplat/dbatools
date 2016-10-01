
Remove-Module dbatools
Import-Module 'C:\Users\csommer\Documents\SCM\dbatools\dbatools.psd1'

$param1 = @{
    	'BackupFolder' = 'C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Backup';
		'BackupFileExtenstion' = 'bak';
        'RetentionPeriod' = '1h' ;
        'CheckArchiveBit' = $true ;
        'RemoveEmptyBackupFolders' = $true ;
        'Verbose' = $false ;
        'WhatIf' = $false
}

cls
Remove-SqlBackupFromDisk @param1 

# Get-Help Remove-SqlBackupFromDisk -Full
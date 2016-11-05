<# INIT

# SQL Services
Remove-Module SQLServiceManagement -ErrorAction SilentlyContinue
Import-Module 'C:\Users\csommer\Documents\SCM\sqlserver-automation-with-posh\SQLServer\SQLServiceManagement.psm1'
Set-SQLServiceStartMode -NewStartMode 'Disabled' -ServiceName 'MsDtsServer120'

Start-SQLServices
Get-SQLServices | Format-Table -AutoSize

# Init Backup Folder for Testing
$BackupLocation = 'C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Backup\DEV-M-234RF'
$TestBackupLocation = 'C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Backup\DEV-M-234RF_TEST'

Get-ChildItem -Path $TestBackupLocation | Remove-Item -Recurse -Force 
Copy-Item -Path $BackupLocation\* -Destination $TestBackupLocation -Recurse
Get-ChildItem $TestBackupLocation -File -Recurse | ForEach-Object { $_.CreationTime = $_.LastWriteTime }

Get-ChildItem $TestBackupLocation

#>

Remove-Module dbatools -ErrorAction SilentlyContinue
Import-Module 'C:\Users\csommer\Documents\SCM\dbatools\dbatools.psd1'


$TestBackupLocation = 'C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Backup\DEV-M-234RF_TEST'

$WhatIfPreference = $false

Remove-DbaBackup -BackupFolder $TestBackupLocation -BackupFileExtension 'bak' -RetentionPeriod '4w' -RemoveEmptyBackupFolders



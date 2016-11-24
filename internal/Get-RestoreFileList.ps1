Function Get-RestoreFileList
{
	param (
		[object]$server,
		[string]$filepath
	)
	
	$restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
	$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem $filepath, "FILE"
	$restore.Devices.Add($device)
	
	try
	{
		$filelist = $restore.ReadFileList($server)
	}
	catch
	{
		Write-Exception $_
		throw "File list could not be determined. This is likely due to connectivity issues or tiemouts with the SQL Server, the database version is incorrect, or the SQL Server service account does not have access to the file share. Script terminating."
	}
	
	$header = $restore.ReadBackupHeader($server)
	$dbname = $header.DatabaseName
	
	[pscustomobject]@{
		Filelist = $filelist
		DatabaseName = $dbname
	}
}
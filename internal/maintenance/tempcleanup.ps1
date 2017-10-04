$scriptBlock = {
	Get-ChildItem -Path $env:TEMP -Filter dbatools*.dll | Remove-Item -ErrorAction Ignore
}
Register-DbaMaintenanceTask -Name "tempcleanup" -ScriptBlock $scriptBlock -Once -Delay (New-TimeSpan -Minutes 1) -Priority Low
$scriptBlock = {
	Get-ChildItem -Path $env:TEMP -Filter dbatools*.dll | Remove-Item -ErrorAction Ignore
}
Register-DbaMaintenanceTask -Name "tempcleanuo" -ScriptBlock $scriptBlock -Once -Delay (New-TimeSpan -Minutes 5) -Priority Low
$scriptBlock = {
    Get-ChildItem -Path $env:TEMP -Filter dbatools* | Remove-Item -ErrorAction Ignore -Recurse
}
Register-DbaMaintenanceTask -Name "tempcleanup" -ScriptBlock $scriptBlock -Once -Delay (New-TimeSpan -Minutes 1) -Priority Low
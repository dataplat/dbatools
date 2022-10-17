$scriptBlock = {
    if (-not $Env:TEMP) {
        $Env:TEMP = [System.IO.Path]::GetTempPath()
    }
    Get-ChildItem -Path $Env:TEMP -Filter dbatools* | Remove-Item -ErrorAction Ignore -Recurse
}
Register-DbaMaintenanceTask -Name "tempcleanup" -ScriptBlock $scriptBlock -Once -Delay (New-TimeSpan -Minutes 1) -Priority Low
$scriptBlock = {
    if (-not $Env:TEMP) {
        $Env:TEMP = [System.IO.Path]::GetTempPath()
    }
    # Commands and tests of this and of every other PowerShell process name their working items dbatools*,
    # so only remove what nobody has written to for a day. That still tidies up after crashed runs.
    $staleBefore = (Get-Date).AddDays(-1)
    # The export folder falls back to the temp folder when the account has no Documents folder.
    $exportPath = Get-DbatoolsConfigValue -FullName "Path.DbatoolsExport"
    if ($exportPath) {
        $exportPath = $exportPath.TrimEnd("\", "/")
    }
    Get-ChildItem -Path $Env:TEMP -Filter dbatools* | Where-Object { $PSItem.LastWriteTime -lt $staleBefore -and $PSItem.FullName.TrimEnd("\", "/") -ne $exportPath } | Remove-Item -ErrorAction Ignore -Recurse
}
Register-DbaMaintenanceTask -Name "tempcleanup" -ScriptBlock $scriptBlock -Once -Delay (New-TimeSpan -Minutes 1) -Priority Low
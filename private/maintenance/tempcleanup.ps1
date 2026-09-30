$scriptBlock = {
    if (-not $Env:TEMP) {
        $Env:TEMP = [System.IO.Path]::GetTempPath()
    }
    # Commands and tests of this and of every other PowerShell process name their working items dbatools*,
    # so only remove what nobody has written to for a day. That still tidies up after crashed runs.
    $staleBefore = (Get-Date).AddDays(-1)

    # The export folder falls back to the temp folder when the account has no Documents folder, and users may point it
    # into the temp folder, also below a dbatools* folder. Neither the export folder nor a folder above it is removed.
    # Both sides are compared in one spelling: GetFullPath makes the path absolute, uses one kind of separator and
    # replaces short 8.3 names like ADMIN~1, which an export path built from TEMP often has.
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $exportPath = Get-DbatoolsConfigValue -FullName "Path.DbatoolsExport"
    if ($exportPath) {
        try {
            $exportPath = [System.IO.Path]::GetFullPath($exportPath).TrimEnd($separator)
        } catch {
            # Without a comparable export path nothing can be told apart safely, so nothing is removed.
            return
        }
    }

    Get-ChildItem -Path $Env:TEMP -Filter dbatools* | Where-Object LastWriteTime -lt $staleBefore | Where-Object {
        if (-not $exportPath) {
            return $true
        }
        $candidatePath = [System.IO.Path]::GetFullPath($PSItem.FullName).TrimEnd($separator)
        $exportPath -ne $candidatePath -and -not $exportPath.StartsWith($candidatePath + $separator, [System.StringComparison]::OrdinalIgnoreCase)
    } | Remove-Item -ErrorAction Ignore -Recurse
}
Register-DbaMaintenanceTask -Name "tempcleanup" -ScriptBlock $scriptBlock -Once -Delay (New-TimeSpan -Minutes 1) -Priority Low
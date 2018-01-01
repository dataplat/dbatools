$scriptBlock = {
    $script:___ScriptName = 'dbatools-logging'

    #region Helper Functions
    function Clean-ErrorXml {
        [CmdletBinding()]
        Param (
            $Path
        )

        $totalLength = $Null
        $files = Get-ChildItem -Path $Path.FullName -Filter "dbatools_$($pid)_error_*.xml" | Sort-Object LastWriteTime
        $totalLength = $files | Measure-Object Length -Sum | Select-Object -ExpandProperty Sum
        if (([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::MaxErrorFileBytes) -gt $totalLength) { return }

        $removed = 0
        foreach ($file in $files) {
            $removed += $file.Length
            Remove-Item -Path $file.FullName -Force -Confirm:$false

            if (($totalLength - $removed) -lt ([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::MaxErrorFileBytes)) { break }
        }
    }

    function Clean-MessageLog {
        [CmdletBinding()]
        Param (
            $Path
        )

        if ([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::MaxMessagefileCount -eq 0) { return }

        $files = Get-ChildItem -Path $Path.FullName -Filter "dbatools_$($pid)_message_*.log" | Sort-Object LastWriteTime
        if (([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::MaxMessagefileCount) -ge $files.Count) { return }

        $removed = 0
        foreach ($file in $files) {
            $removed++
            Remove-Item -Path $file.FullName -Force -Confirm:$false

            if (($files.Count - $removed) -le ([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::MaxMessagefileCount)) { break }
        }
    }

    function Clean-GlobalLog {
        [CmdletBinding()]
        Param (
            $Path
        )

        # Kill too old files
        Get-ChildItem -Path "$($Path.FullName)\*" -Include "*.xml", "*.log" -Filter "*" | Where-Object LastWriteTime -LT ((Get-Date) - ([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::MaxLogFileAge)) |Remove-Item -Force -Confirm:$false

        # Handle the global overcrowding
        $files = Get-ChildItem -Path "$($Path.FullName)\*" -Include "*.xml", "*.log" -Filter "*" | Sort-Object LastWriteTime
        if (-not ($files)) { return }
        $totalLength = $files | Measure-Object Length -Sum | Select-Object -ExpandProperty Sum

        if (([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::MaxTotalFolderSize) -gt $totalLength) { return }

        $removed = 0
        foreach ($file in $files) {
            $removed += $file.Length
            Remove-Item -Path $file.FullName -Force -Confirm:$false

            if (($totalLength - $removed) -lt ([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::MaxTotalFolderSize)) { break }
        }
    }
    #endregion Helper Functions

    try {
        while ($true) {
            # This portion is critical to gracefully closing the script
            if ([Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLower()].State -notlike "Running") {
                break
            }

            $path = [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::LoggingPath
            if (-not (Test-Path $path)) {
                $root = New-Item $path -ItemType Directory -Force -ErrorAction Stop
            }
            else { $root = Get-Item -Path $path }

            try { [int]$num_Error = (Get-ChildItem -Path $root.FullName -Filter "dbatools_$($pid)_error_*.xml" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty Name | Select-String -Pattern "(\d+)" -AllMatches).Matches[1].Value }
            catch { }
            try { [int]$num_Message = (Get-ChildItem -Path $root.FullName -Filter "dbatools_$($pid)_message_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty Name | Select-String -Pattern "(\d+)" -AllMatches).Matches[1].Value }
            catch { }
            if (-not ($num_Error)) { $num_Error = 0 }
            if (-not ($num_Message)) { $num_Message = 0 }

            #region Process Errors
            while ([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::OutQueueError.Count -gt 0) {
                $num_Error++

                $Record = $null
                [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::OutQueueError.TryDequeue([ref]$Record)

                if ($Record) {
                    $Record | Export-Clixml -Path "$($root.FullName)\dbatools_$($pid)_error_$($num_Error).xml" -Depth 3
                }

                Clean-ErrorXml -Path $root
            }
            #endregion Process Errors

            #region Process Logs
            while ([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::OutQueueLog.Count -gt 0) {
                $CurrentFile = "$($root.FullName)\dbatools_$($pid)_message_$($num_Message).log"
                if (Test-Path $CurrentFile) {
                    $item = Get-Item $CurrentFile
                    if ($item.Length -gt ([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::MaxMessagefileBytes)) {
                        $num_Message++
                        $CurrentFile = "$($root.FullName)\dbatools_$($pid)_message_$($num_Message).log"
                    }
                }

                $Entry = $null
                [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::OutQueueLog.TryDequeue([ref]$Entry)
                if ($Entry) {
                    Add-Content -Path $CurrentFile -Value (ConvertTo-Csv -InputObject $Entry -NoTypeInformation)[1]
                }
            }
            #endregion Process Logs

            Clean-MessageLog -Path $root
            Clean-GlobalLog -Path $root

            Start-Sleep -Seconds 5
        }
    }
    catch { }
    finally {
        [Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLower()].SignalStopped()
    }
}

Register-DbaRunspace -ScriptBlock $scriptBlock -Name "dbatools-logging"
Start-DbaRunspace -Name "dbatools-logging"
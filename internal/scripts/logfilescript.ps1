$scriptBlock = {
    #region Helper Functions
    function Clean-ErrorXml
    {
        [CmdletBinding()]
        Param (
            $Path
        )
        
        $totalLength = $Null
        $files = Get-ChildItem -Path $Path.FullName -Filter "dbatools_$($pid)_error_*.xml" | Sort-Object LastWriteTime
        $totalLength = $files | Measure-Object Length -Sum | Select-Object -ExpandProperty Sum
        if (([sqlcollective.dbatools.dbaSystem.DebugHost]::MaxErrorFileBytes) -gt $totalLength) { return }
        
        $removed = 0
        foreach ($file in $files)
        {
            $removed += $file.Length
            Remove-Item -Path $file.FullName -Force -Confirm:$false
            
            if (($totalLength - $removed) -lt ([sqlcollective.dbatools.dbaSystem.DebugHost]::MaxErrorFileBytes)) { break }
        }
    }
    
    function Clean-MessageLog
    {
        [CmdletBinding()]
        Param (
            $Path
        )
        
        if ([sqlcollective.dbatools.dbaSystem.DebugHost]::MaxMessagefileCount -eq 0) { return }
        
        $files = Get-ChildItem -Path $Path.FullName -Filter "dbatools_$($pid)_message_*.log" | Sort-Object LastWriteTime
        if (([sqlcollective.dbatools.dbaSystem.DebugHost]::MaxMessagefileCount) -ge $files.Count) { return }
        
        $removed = 0
        foreach ($file in $files)
        {
            $removed++
            Remove-Item -Path $file.FullName -Force -Confirm:$false
            
            if (($files.Count - $removed) -le ([sqlcollective.dbatools.dbaSystem.DebugHost]::MaxMessagefileCount)) { break }
        }
    }
    
    function Clean-GlobalLog
    {
        [CmdletBinding()]
        Param (
            $Path
        )
        
        # Kill too old files
        Get-ChildItem -Path "$($Path.FullName)\*" -Include "*.xml", "*.log" -Filter "*" | Where-Object LastWriteTime -LT ((Get-Date) - ([sqlcollective.dbatools.dbaSystem.DebugHost]::MaxLogFileAge)) |Remove-Item -Force -Confirm:$false
        
        # Handle the global overcrowding
        $files = Get-ChildItem -Path "$($Path.FullName)\*" -Include "*.xml", "*.log" -Filter "*" | Sort-Object LastWriteTime
        if (-not ($files)) { return }
        $totalLength = $files | Measure-Object Length -Sum | Select-Object -ExpandProperty Sum
        
        if (([sqlcollective.dbatools.dbaSystem.DebugHost]::MaxTotalFolderSize) -gt $totalLength) { return }
        
        $removed = 0
        foreach ($file in $files)
        {
            $removed += $file.Length
            Remove-Item -Path $file.FullName -Force -Confirm:$false
            
            if (($totalLength - $removed) -lt ([sqlcollective.dbatools.dbaSystem.DebugHost]::MaxTotalFolderSize)) { break }
        }
    }
    #endregion Helper Functions

    
    while ($true)
    {
        # This portion is critical to gracefully closing the script
        if ([sqlcollective.dbatools.dbaSystem.LogWriterHost]::LogWriterStopper)
        {
            exit
        }
        
        $path = [sqlcollective.dbatools.dbaSystem.DebugHost]::LoggingPath
        if (-not (Test-Path $path))
        {
            $root = New-Item $path -ItemType Directory -Force -ErrorAction Stop
        }
        else { $root = Get-Item -Path $path }
        
        [int]$num_Error = (Get-ChildItem -Path $Path.FullName -Filter "dbatools_$($pid)_error_*.xml" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty Name | Select-String -Pattern "(\d+)" -AllMatches).Matches[1].Value
        [int]$num_Message = (Get-ChildItem -Path $Path.FullName -Filter "dbatools_$($pid)_message_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty Name | Select-String -Pattern "(\d+)" -AllMatches).Matches[1].Value
        if (-not ($num_Error)) { $num_Error = 0 }
        if (-not ($num_Message)) { $num_Message = 0 }
        
        #region Process Errors
        while ([sqlcollective.dbatools.dbaSystem.DebugHost]::OutQueueError.Count -gt 0)
        {
            $num_Error++
            
            $Record = $null
            [sqlcollective.dbatools.dbaSystem.DebugHost]::OutQueueError.TryDequeue([ref]$Record)
            
            if ($Record)
            {
                $Record | Export-Clixml -Path "$($root.FullName)\dbatools_$($pid)_error_$($num_Error).xml"
            }
            
            Clean-ErrorXml -Path $root
        }
        #endregion Process Errors
        
        #region Process Logs
        while ([sqlcollective.dbatools.dbaSystem.DebugHost]::OutQueueLog.Count -gt 0)
        {
            $CurrentFile = "$($root.FullName)\dbatools_$($pid)_message_$($num_Message).log"
            if (Test-Path $CurrentFile)
            {
                $item = Get-Item $CurrentFile
                if ($item.Length -gt ([sqlcollective.dbatools.dbaSystem.DebugHost]::MaxMessagefileBytes))
                {
                    $num_Message++
                    $CurrentFile = "$($root.FullName)\dbatools_$($pid)_message_$($num_Message).log"
                }
            }
            
            $Entry = $null
            [sqlcollective.dbatools.dbaSystem.DebugHost]::OutQueueLog.TryDequeue([ref]$Entry)
            if ($Entry)
            {
                Add-Content -Path $CurrentFile -Value (ConvertTo-Csv -InputObject $Entry -NoTypeInformation)[1]
            }
        }
        #endregion Process Logs
        
        Clean-MessageLog -Path $root
        Clean-GlobalLog -Path $root
        
        Start-Sleep -Seconds 5
    }
}

[sqlcollective.dbatools.dbaSystem.LogWriterHost]::SetScript($scriptBlock)
[sqlcollective.dbatools.dbaSystem.LogWriterHost]::Start()
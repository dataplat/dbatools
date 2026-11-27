$scriptBlock = {
    $script:___ScriptName = 'dbatools-logging'

    #region Helper Functions
    function Clean-ErrorXml {
        [CmdletBinding()]
        param (
            $Path
        )

        $totalLength = $Null
        $files = Get-ChildItem -Path $Path.FullName -Filter "dbatools_$($pid)_error_*.xml" | Sort-Object LastWriteTime
        $totalLength = $files | Measure-Object Length -Sum | Select-Object -ExpandProperty Sum
        if (([Dataplat.Dbatools.Message.LogHost]::MaxErrorFileBytes) -gt $totalLength) { return }

        $removed = 0
        foreach ($file in $files) {
            $removed += $file.Length
            Remove-Item -Path $file.FullName -Force -Confirm:$false

            if (($totalLength - $removed) -lt ([Dataplat.Dbatools.Message.LogHost]::MaxErrorFileBytes)) { break }
        }
    }

    function Clean-MessageLog {
        [CmdletBinding()]
        param (
            $Path
        )

        if ([Dataplat.Dbatools.Message.LogHost]::MaxMessagefileCount -eq 0) { return }

        $files = Get-ChildItem -Path $Path.FullName -Filter "dbatools_$($pid)_message_*.log" | Sort-Object LastWriteTime
        if (([Dataplat.Dbatools.Message.LogHost]::MaxMessagefileCount) -ge $files.Count) { return }

        $removed = 0
        foreach ($file in $files) {
            $removed++
            Remove-Item -Path $file.FullName -Force -Confirm:$false

            if (($files.Count - $removed) -le ([Dataplat.Dbatools.Message.LogHost]::MaxMessagefileCount)) { break }
        }
    }

    function Clean-GlobalLog {
        [CmdletBinding()]
        param (
            $Path
        )

        # Kill too old files
        Get-ChildItem -Path "$($Path.FullName)\*" -Include "*.xml", "*.log" -Filter "*" | Where-Object LastWriteTime -LT ((Get-Date) - ([Dataplat.Dbatools.Message.LogHost]::MaxLogFileAge)) |Remove-Item -Force -Confirm:$false

        # Handle the global overcrowding
        $files = Get-ChildItem -Path "$($Path.FullName)\*" -Include "*.xml", "*.log" -Filter "*" | Sort-Object LastWriteTime
        if (-not ($files)) { return }
        $totalLength = $files | Measure-Object Length -Sum | Select-Object -ExpandProperty Sum

        if (([Dataplat.Dbatools.Message.LogHost]::MaxTotalFolderSize) -gt $totalLength) { return }

        $removed = 0
        foreach ($file in $files) {
            $removed += $file.Length
            Remove-Item -Path $file.FullName -Force -Confirm:$false

            if (($totalLength - $removed) -lt ([Dataplat.Dbatools.Message.LogHost]::MaxTotalFolderSize)) { break }
        }
    }
    #endregion Helper Functions

    # The line of a record that a pass took from the queue but could not write, kept for the next pass.
    $pendingLine = $null
    try {
        while ($true) {
            # This portion is critical to gracefully closing the script
            if ([Dataplat.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLowerInvariant()].State -notlike "Running") {
                break
            }

            $path = [Dataplat.Dbatools.Message.LogHost]::LoggingPath
            if (-not (Test-Path $path)) {
                $root = New-Item $path -ItemType Directory -Force -ErrorAction Stop
            } else {
                $root = Get-Item -Path $path
            }

            $errorFiles = Get-ChildItem -Path $root.FullName -Filter "dbatools_$($pid)_error_*.xml" | Sort-Object LastWriteTime -Descending
            [int]$num_Error = if ($errorFiles) {
                (Select-String -InputObject $errorFiles[0].Name -Pattern "(\d+)" -AllMatches).Matches[1].Value
            } else {
                0
            }

            $messageFiles = Get-ChildItem -Path $root.FullName -Filter "dbatools_$($pid)_message_*.log" | Sort-Object LastWriteTime -Descending
            [int]$num_Message = if ($messageFiles) {
                (Select-String -InputObject $messageFiles[0].Name -Pattern "(\d+)" -AllMatches).Matches[1].Value
            } else {
                0
            }

            #region Process Errors
            while ([Dataplat.Dbatools.Message.LogHost]::OutQueueError.Count -gt 0) {
                $num_Error++

                $Record = $null
                $null = [Dataplat.Dbatools.Message.LogHost]::OutQueueError.TryDequeue([ref]$Record)

                if ($Record) {
                    $Record | Export-Clixml -Path "$($root.FullName)\dbatools_$($pid)_error_$($num_Error).xml" -Depth 3
                }

                Clean-ErrorXml -Path $root
            }
            #endregion Process Errors

            #region Process Logs
            # A pass writes the queued records through one open file and flushes it after every record. Opening and
            # closing the file for every record made a virus scanner rescan the whole file every time: with real time
            # protection the writer managed about six records per second against a 5 MB file and fell hours behind a busy
            # session. The file shares reading, so readers that share writing (Get-Content, Select-String) can read it
            # meanwhile. A record is only taken from the queue once the file is open, and a record that could not be
            # written waits in $pendingLine, so a file that refuses to be opened or written loses nothing: the next pass
            # tries again. A pass ends after five seconds, so that the cleanup below also runs while records keep coming.
            # A MaxMessagefileBytes of 0 means no limit, so the file only changes when a limit is set and reached.
            $maxMessagefileBytes = [Dataplat.Dbatools.Message.LogHost]::MaxMessagefileBytes
            $passTimer = [System.Diagnostics.Stopwatch]::StartNew()
            $passFull = $false
            $writer = $null
            try {
                while ($pendingLine -or [Dataplat.Dbatools.Message.LogHost]::OutQueueLog.Count -gt 0) {
                    if ($passTimer.Elapsed.TotalSeconds -ge 5) {
                        $passFull = $true
                        break
                    }

                    if ($writer -and $maxMessagefileBytes -gt 0 -and $writer.BaseStream.Length -gt $maxMessagefileBytes) {
                        $writer.Dispose()
                        $writer = $null
                        $num_Message++
                    }
                    if (-not $writer) {
                        $CurrentFile = "$($root.FullName)\dbatools_$($pid)_message_$($num_Message).log"
                        if ($maxMessagefileBytes -gt 0 -and (Test-Path -Path $CurrentFile) -and (Get-Item -Path $CurrentFile).Length -gt $maxMessagefileBytes) {
                            $num_Message++
                            $CurrentFile = "$($root.FullName)\dbatools_$($pid)_message_$($num_Message).log"
                        }
                        $fileStream = New-Object -TypeName System.IO.FileStream -ArgumentList $CurrentFile, ([System.IO.FileMode]::Append), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::Read) -ErrorAction Stop
                        # The default encoding of Add-Content in both editions, which wrote these files before.
                        $writer = New-Object -TypeName System.IO.StreamWriter -ArgumentList $fileStream, ([System.Text.Encoding]::Default)
                    }

                    if (-not $pendingLine) {
                        $Entry = $null
                        $null = [Dataplat.Dbatools.Message.LogHost]::OutQueueLog.TryDequeue([ref]$Entry)
                        if (-not $Entry) {
                            continue
                        }
                        # ConvertTo-Csv calls ToString() on every property, which returns the type name for the list of tags.
                        # So we join the tags into one string and keep all other columns in their order.
                        $csvProperties = foreach ($propertyName in $Entry.PSObject.Properties.Name) {
                            if ($propertyName -eq "Tags") {
                                @{
                                    Name       = "Tags"
                                    Expression = { $PSItem.Tags -join ", " }
                                }
                            } else {
                                $propertyName
                            }
                        }
                        $csvEntry = $Entry | Select-Object -Property $csvProperties
                        $pendingLine = (ConvertTo-Csv -InputObject $csvEntry -NoTypeInformation)[1]
                    }
                    $writer.WriteLine($pendingLine)
                    $writer.Flush()
                    $pendingLine = $null
                }
            } catch {
                # The file refused to be opened or written, for example because another program holds it without sharing
                # writing. The records wait for the next pass.
                $null = 1
            } finally {
                if ($writer) {
                    $writer.Dispose()
                }
            }
            #endregion Process Logs

            Clean-MessageLog -Path $root
            Clean-GlobalLog -Path $root

            # A pass that ran out of time leaves records in the queue, so the next one starts right away.
            if (-not $passFull) {
                Start-Sleep -Seconds 5
            }
        }
    } catch { }
    finally {
        [Dataplat.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLowerInvariant()].SignalStopped()
    }
}

Register-DbaRunspace -ScriptBlock $scriptBlock -Name "dbatools-logging"
Start-DbaRunspace -Name "dbatools-logging"
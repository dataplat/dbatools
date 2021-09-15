function Invoke-DbaPfRelog {
    <#
    .SYNOPSIS
        Pipeline-compatible wrapper for the relog command which is available on modern Windows platforms.

    .DESCRIPTION
        Pipeline-compatible wrapper for the relog command. Relog is useful for converting Windows Perfmon.

        Extracts performance counters from performance counter logs into other formats,
        such as text-TSV (for tab-delimited text), text-CSV (for comma-delimited text), binary-BIN, or SQL.

        `relog "C:\PerfLogs\Admin\System Correlation\WORKSTATIONX_20180112-000001\DataCollector01.blg" -o C:\temp\foo.csv -f tsv`

        If you find any input hangs, please send us the output so we can accommodate for it then use -Raw for an immediate solution.

    .PARAMETER Path
        Specifies the pathname of an existing performance counter log or performance counter path. You can specify multiple input files.

    .PARAMETER Destination
        Specifies the pathname of the output file or SQL database where the counters will be written. Defaults to the same directory as the source.

    .PARAMETER Type
        The output format. Defaults to tsv. Options include tsv, csv, bin, and sql.

        For a SQL database, the output file specifies the DSN!counter_log. You can specify the database location by using the ODBC manager to configure the DSN (Database System Name).

        For more information, read here: https://technet.microsoft.com/en-us/library/bb490958.aspx

    .PARAMETER Append
        If this switch is enabled, output will be appended to the specified file instead of overwriting. This option does not apply to SQL format where the default is always to append.

    .PARAMETER AllowClobber
        If this switch is enabled, the destination file will be overwritten if it exists.

    .PARAMETER PerformanceCounter
        Specifies the performance counter path to log.

    .PARAMETER PerformanceCounterPath
        Specifies the pathname of the text file that lists the performance counters to be included in a relog file. Use this option to list counter paths in an input file, one per line. Default setting is all counters in the original log file are relogged.

    .PARAMETER Interval
        Specifies sample intervals in "n" records. Includes every nth data point in the relog file. Default is every data point.

    .PARAMETER BeginTime
        This is is Get-Date object and we format it for you.

    .PARAMETER EndTime
        Specifies end time for copying last record from the input file. This is is Get-Date object and we format it for you.

    .PARAMETER ConfigPath
        Specifies the pathname of the settings file that contains command-line parameters.

    .PARAMETER Summary
        If this switch is enabled, the performance counters and time ranges of log files specified in the input file will be displayed.

    .PARAMETER Multithread
        If this switch is enabled, processing will be done in parallel. This may speed up large batches or large files.

    .PARAMETER AllTime
        If this switch is enabled and a datacollector or datacollectorset is passed in via the pipeline, collects all logs, not just the latest.

    .PARAMETER Raw
        If this switch is enabled, the results of the DOS command instead of Get-ChildItem will be displayed. This does not run in parallel.

    .PARAMETER InputObject
        Accepts the output of Get-DbaPfDataCollector and Get-DbaPfDataCollectorSet as input via the pipeline.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Performance, DataCollector, PerfCounter, Relog
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaPfRelog

    .EXAMPLE
        PS C:\> Invoke-DbaPfRelog -Path C:\temp\perfmon.blg

        Creates C:\temp\perfmon.tsv from C:\temp\perfmon.blg.

    .EXAMPLE
        PS C:\> Invoke-DbaPfRelog -Path C:\temp\perfmon.blg -Destination C:\temp\a\b\c

        Creates the temp, a, and b directories if needed, then generates c.tsv (tab separated) from C:\temp\perfmon.blg.

        Returns the newly created file as a file object.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSet -ComputerName sql2016 | Get-DbaPfDataCollector | Invoke-DbaPfRelog -Destination C:\temp\perf

        Creates C:\temp\perf if needed, then generates computername-datacollectorname.tsv (tab separated) from the latest logs of all data collector sets on sql2016. This destination format was chosen to avoid naming conflicts with piped input.

    .EXAMPLE
        PS C:\> Invoke-DbaPfRelog -Path C:\temp\perfmon.blg -Destination C:\temp\a\b\c -Raw
        ```
        [Invoke-DbaPfRelog][21:21:35] relog "C:\temp\perfmon.blg" -f csv -o C:\temp\a\b\c

        Input
        ----------------
        File(s):
        C:\temp\perfmon.blg (Binary)

        Begin:    1/13/2018 5:13:23
        End:      1/13/2018 14:29:55
        Samples:  2227

        100.00%

        Output
        ----------------
        File:     C:\temp\a\b\c.csv

        Begin:    1/13/2018 5:13:23
        End:      1/13/2018 14:29:55
        Samples:  2227

        The command completed successfully.
        ```

        Creates the temp, a, and b directories if needed, then generates c.tsv (tab separated) from C:\temp\perfmon.blg then outputs the raw results of the relog command.

    .EXAMPLE
        PS C:\> Invoke-DbaPfRelog -Path 'C:\temp\perflog with spaces.blg' -Destination C:\temp\a\b\c -Type csv -BeginTime ((Get-Date).AddDays(-30)) -EndTime ((Get-Date).AddDays(-1))

        Creates the temp, a, and b directories if needed, then generates c.csv (comma separated) from C:\temp\perflog with spaces.blg', starts 30 days ago and ends one day ago.

    .EXAMPLE
        PS C:\> $servers | Get-DbaPfDataCollectorSet | Get-DbaPfDataCollector | Invoke-DbaPfRelog -Multithread -AllowClobber

        Relogs latest data files from all collectors within the servers listed in $servers.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollector -Collector DataCollector01 | Invoke-DbaPfRelog -AllowClobber -AllTime

        Relogs all the log files from the DataCollector01 on the local computer and allows overwrite.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipelineByPropertyName)]
        [Alias("FullName")]
        [string[]]$Path,
        [string]$Destination,
        [ValidateSet("tsv", "csv", "bin", "sql")]
        [string]$Type = "tsv",
        [switch]$Append,
        [switch]$AllowClobber,
        [string[]]$PerformanceCounter,
        [string]$PerformanceCounterPath,
        [int]$Interval,
        [datetime]$BeginTime,
        [datetime]$EndTime,
        [string]$ConfigPath,
        [switch]$Summary,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$Multithread,
        [switch]$AllTime,
        [switch]$Raw,
        [switch]$EnableException
    )
    begin {


        if (Test-Bound -ParameterName BeginTime) {
            $script:beginstring = ($BeginTime -f 'M/d/yyyy hh:mm:ss' | Out-String).Trim()
        }
        if (Test-Bound -ParameterName EndTime) {
            $script:endstring = ($EndTime -f 'M/d/yyyy hh:mm:ss' | Out-String).Trim()
        }

        $allpaths = @()
        $allpaths += $Path

        # to support multithreading
        if (Test-Bound -ParameterName Destination) {
            $script:destinationset = $true
            $originaldestination = $Destination
        } else {
            $script:destinationset = $false
        }
    }
    process {
        if ($Append -and $Type -ne "bin") {
            Stop-Function -Message "Append can only be used with -Type bin." -Target $Path
            return
        }

        if ($InputObject) {
            foreach ($object in $InputObject) {
                # DataCollectorSet
                if ($object.OutputLocation -and $object.RemoteOutputLocation) {
                    $instance = [dbainstance]$object.ComputerName

                    if (-not $AllTime) {
                        if ($instance.IsLocalHost) {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.LatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        } else {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.RemoteLatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        }
                    } else {
                        if ($instance.IsLocalHost) {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.OutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        } else {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.RemoteOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        }
                    }


                    $script:perfmonobject = $true
                }
                # DataCollector
                if ($object.LatestOutputLocation -and $object.RemoteLatestOutputLocation) {
                    $instance = [dbainstance]$object.ComputerName

                    if (-not $AllTime) {
                        if ($instance.IsLocalHost) {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.LatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        } else {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.RemoteLatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        }
                    } else {
                        if ($instance.IsLocalHost) {
                            $allpaths += (Get-ChildItem -Recurse -Path (Split-Path $object.LatestOutputLocation) -Include *.blg -ErrorAction SilentlyContinue).FullName
                        } else {
                            $allpaths += (Get-ChildItem -Recurse -Path (Split-Path $object.RemoteLatestOutputLocation) -Include *.blg -ErrorAction SilentlyContinue).FullName
                        }
                    }
                    $script:perfmonobject = $true
                }
            }
        }
    }

    # Gotta collect all the paths first then process them otherwise there may be duplicates
    end {
        $allpaths = $allpaths | Where-Object { $_ -match '.blg' } | Select-Object -Unique

        if (-not $allpaths) {
            Stop-Function -Message "Could not find matching .blg files" -Target $file -Continue
            return
        }

        $scriptBlock = {
            if ($args) {
                $file = $args
            } else {
                $file = $psitem
            }
            $item = Get-ChildItem -Path $file -ErrorAction SilentlyContinue

            if ($null -eq $item) {
                Stop-Function -Message "$file does not exist." -Target $file -Continue
                return
            }

            if (-not $script:destinationset -and $file -match "C\:\\.*Admin.*") {
                $null = Test-ElevationRequirement -ComputerName $env:COMPUTERNAME -Continue
            }

            if ($script:destinationset -eq $false -and -not $Append) {
                $Destination = Join-Path (Split-Path $file) $item.BaseName
            }

            if ($Destination -and $Destination -notmatch "\." -and -not $Append -and $script:perfmonobject) {
                # if destination is set, then it needs a different name
                if ($script:destinationset -eq $true) {
                    if ($file -match "\:") {
                        $computer = $env:COMPUTERNAME
                    } else {
                        $computer = $file.Split("\")[2]
                    }
                    # Avoid naming conflicts
                    $timestamp = Get-Date -format yyyyMMddHHmmfff
                    $Destination = Join-Path $originaldestination "$computer - $($item.BaseName) - $timestamp"
                }
            }

            $params = @("`"$file`"")

            if ($Append) {
                $params += "-a"
            }

            if ($PerformanceCounter) {
                $parsedcounters = $PerformanceCounter -join " "
                $params += "-c `"$parsedcounters`""
            }

            if ($PerformanceCounterPath) {
                $params += "-cf `"$PerformanceCounterPath`""
            }

            $params += "-f $Type"

            if ($Interval) {
                $params += "-t $Interval"
            }

            if ($Destination) {
                $params += "-o `"$Destination`""
            }

            if ($script:beginstring) {
                $params += "-b $script:beginstring"
            }

            if ($script:endstring) {
                $params += "-e $script:endstring"
            }

            if ($ConfigPath) {
                $params += "-config $ConfigPath"
            }

            if ($Summary) {
                $params += "-q"
            }


            if (-not ($Destination.StartsWith("DSN"))) {
                $outputisfile = $true
            } else {
                $outputisfile = $false
            }

            if ($outputisfile) {
                if ($Destination) {
                    $dir = Split-Path $Destination
                    if (-not (Test-Path -Path $dir)) {
                        try {
                            $null = New-Item -ItemType Directory -Path $dir -ErrorAction Stop
                        } catch {
                            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $Destination -Continue
                        }
                    }

                    if ((Test-Path $Destination) -and -not $Append -and ((Get-Item $Destination) -isnot [System.IO.DirectoryInfo])) {
                        if ($AllowClobber) {
                            try {
                                Remove-Item -Path "$Destination" -ErrorAction Stop
                            } catch {
                                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                            }
                        } else {
                            if ($Type -eq "bin") {
                                Stop-Function -Message "$Destination exists. Use -AllowClobber to overwrite or -Append to append." -Continue
                            } else {
                                Stop-Function -Message "$Destination exists. Use -AllowClobber to overwrite." -Continue
                            }
                        }
                    }

                    if ((Test-Path "$Destination.$type") -and -not $Append) {
                        if ($AllowClobber) {
                            try {
                                Remove-Item -Path "$Destination.$type" -ErrorAction Stop
                            } catch {
                                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                            }
                        } else {
                            if ($Type -eq "bin") {
                                Stop-Function -Message "$("$Destination.$type") exists. Use -AllowClobber to overwrite or -Append to append." -Continue
                            } else {
                                Stop-Function -Message "$("$Destination.$type") exists. Use -AllowClobber to overwrite." -Continue
                            }
                        }
                    }
                }
            }

            $arguments = ($params -join " ")

            try {
                if ($Raw) {
                    Write-Message -Level Output -Message "relog $arguments"
                    cmd /c "relog $arguments"
                } else {
                    Write-Message -Level Verbose -Message "relog $arguments"
                    $scriptBlock = {
                        $output = (cmd /c "relog $arguments" | Out-String).Trim()

                        if ($output -notmatch "Success") {
                            Stop-Function -Continue -Message $output.Trim("Input")
                        } else {
                            Write-Message -Level Verbose -Message "$output"
                            $array = $output -Split [environment]::NewLine
                            $files = $array | Select-String "File:"

                            foreach ($rawfile in $files) {
                                $rawfile = $rawfile.ToString().Replace("File:", "").Trim()
                                $gcierror = $null
                                Get-ChildItem $rawfile -ErrorAction SilentlyContinue -ErrorVariable gcierror | Add-Member -MemberType NoteProperty -Name RelogFile -Value $true -PassThru -ErrorAction Ignore
                                if ($gcierror) {
                                    Write-Message -Level Verbose -Message "$gcierror"
                                }
                            }
                        }
                    }
                    Invoke-Command -ScriptBlock $scriptBlock
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $path
            }
        }

        if ($Multithread) {
            $allpaths | Invoke-Parallel -ImportVariables -ImportModules -ScriptBlock $scriptBlock -ErrorAction SilentlyContinue -ErrorVariable parallelerror
            if ($parallelerror) {
                Write-Message -Level Verbose -Message "$parallelerror"
            }
        } else {
            foreach ($file in $allpaths) { Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $file }
        }
    }
}
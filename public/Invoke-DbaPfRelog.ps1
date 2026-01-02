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
        Specifies the file path to Windows performance counter log files (.blg format) that need to be converted. Accepts multiple file paths and supports pipeline input.
        Use this when you have perfmon binary logs that need to be converted to readable formats like CSV or TSV for analysis.

    .PARAMETER Destination
        Specifies the output file path or directory where converted performance data will be saved. Creates necessary directories automatically if they don't exist.
        When omitted, files are saved in the same directory as the source with the appropriate extension (.tsv, .csv, etc.).

    .PARAMETER Type
        Specifies the output format for the converted performance data. Defaults to 'tsv' (tab-separated values).
        Use 'csv' for Excel compatibility, 'tsv' for easy parsing in PowerShell, 'bin' for binary format, or 'sql' to write directly to a SQL database via ODBC.
        For SQL output, specify the destination as 'DSN!counter_log' where DSN is configured in ODBC Manager.

    .PARAMETER Append
        Appends performance data to an existing output file instead of overwriting it. Only works with binary (-Type bin) format.
        Use this when consolidating multiple perfmon logs into a single file for comprehensive analysis over time periods.

    .PARAMETER AllowClobber
        Overwrites existing output files without prompting. Required when the destination file already exists and you want to replace it.
        Use this in automated scripts or when you need to refresh converted performance data files.

    .PARAMETER PerformanceCounter
        Specifies specific performance counters to extract from the log files. Accepts counter paths like '\Processor(_Total)\% Processor Time'.
        Use this to filter large perfmon logs and extract only the counters you need for analysis, reducing output file size.

    .PARAMETER PerformanceCounterPath
        Specifies a text file containing performance counter paths to extract, one counter per line. Alternative to specifying counters directly.
        Use this when you have a standard set of counters for monitoring SQL Server performance and want to consistently extract the same metrics across multiple log files.

    .PARAMETER Interval
        Specifies the sampling interval by including every nth data point from the original log. Reduces output size by skipping intermediate samples.
        Use this when working with high-frequency perfmon logs where you need less granular data for trend analysis rather than detailed monitoring.

    .PARAMETER BeginTime
        Specifies the start time for data extraction using a DateTime object. Only performance data from this time forward will be included in the output.
        Use this to extract specific time periods from large perfmon logs, such as during a known performance incident or maintenance window.

    .PARAMETER EndTime
        Specifies the end time for data extraction using a DateTime object. Performance data after this time will be excluded from the output.
        Combine with BeginTime to extract data from specific time ranges, useful for analyzing performance during particular events or time periods.

    .PARAMETER ConfigPath
        Specifies a configuration file containing relog command-line parameters for complex or frequently-used conversion settings.
        Use this when you have standardized performance log processing requirements that need consistent parameters across multiple operations.

    .PARAMETER Summary
        Displays summary information about the performance log files including available counters and time ranges without performing the conversion.
        Use this to examine perfmon logs before processing them, helping you determine what counters are available and the time span covered.

    .PARAMETER Multithread
        Processes multiple performance log files in parallel to improve performance when converting large batches of files.
        Use this when converting many perfmon logs simultaneously, especially beneficial on multi-core systems with large performance monitoring datasets.

    .PARAMETER AllTime
        Processes all available log files from data collectors instead of just the most recent ones when used with pipeline input from Get-DbaPfDataCollector.
        Use this when you need to convert historical performance data from all collection periods, not just the latest monitoring session.

    .PARAMETER Raw
        Displays the raw output from the relog command instead of returning file objects. Useful for debugging conversion issues or seeing detailed progress.
        Use this when troubleshooting relog operations or when you need to see the exact command-line output and statistics from the conversion process.

    .PARAMETER InputObject
        Accepts data collector objects from Get-DbaPfDataCollector and Get-DbaPfDataCollectorSet via pipeline input for automatic log file discovery.
        Use this to convert performance logs directly from active or configured data collectors without manually specifying file paths.

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

    .OUTPUTS
        System.IO.FileInfo (default)

        Returns file objects for each successfully converted performance log file. Each file object includes all standard System.IO.FileInfo properties plus an added RelogFile property.

        Properties:
        - FullName: The complete path to the converted output file
        - Name: The file name with extension (.tsv, .csv, .bin, etc.)
        - Directory: The directory containing the file
        - DirectoryName: The full path of the directory
        - Extension: The file extension (.tsv, .csv, .bin, .sql)
        - Length: The size of the file in bytes
        - Attributes: File attributes (Archive, ReadOnly, etc.)
        - CreationTime: The date and time the file was created
        - LastAccessTime: The date and time the file was last accessed
        - LastWriteTime: The date and time the file was last modified
        - RelogFile: Boolean NoteProperty set to true, indicating this file was created by relog conversion

        String (when -Raw is specified)

        Returns the raw output from the relog command including:
        - Input file information (file path, format, begin/end times, sample count)
        - Output file information (file path, format, begin/end times, sample count)
        - Completion status message
        - Processing progress percentage

        No output (when -Summary or -ExportQueries is specified)

        When -Summary is used, summary information is displayed as text output but no objects are returned.
        When relog output is written directly to SQL via ODBC, no file objects are available for return.

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
        >> [Invoke-DbaPfRelog][21:21:35] relog "C:\temp\perfmon.blg" -f csv -o C:\temp\a\b\c
        >> Input
        >> ----------------
        >> File(s):
        >> C:\temp\perfmon.blg (Binary)
        >> Begin:    1/13/2018 5:13:23
        >> End:      1/13/2018 14:29:55
        >> Samples:  2227
        >> 100.00%
        >> Output
        >> ----------------
        >> File:     C:\temp\a\b\c.csv
        >> Begin:    1/13/2018 5:13:23
        >> End:      1/13/2018 14:29:55
        >> Samples:  2227
        >> The command completed successfully.

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
                $file = $PSItem
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
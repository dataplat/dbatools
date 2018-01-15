function Invoke-DbaPfRelog {
 <#
    .SYNOPSIS
    Pipable wrapper for the relog command which is available on modern Windows platforms.

    .DESCRIPTION
    Pipable wrapper for the relog command. Relog is useful for converting Windows Perfmon.

    Extracts performance counters from performance counter logs into other formats,
    such as text-TSV (for tab-delimited text), text-CSV (for comma-delimited text), binary-BIN, or SQL.

    relog "C:\PerfLogs\Admin\System Correlation\WORKSTATIONX_20180112-000001\DataCollector01.blg" -o C:\temp\foo.csv -f tsv
    
    *** if you find any command hangs, please send us the output so we can accomdoate for it ** then use -Raw for an immediate solution

    .PARAMETER Path
    Specifies the pathname of an existing performance counter log or performance counter path. You can specify multiple input files.

    .PARAMETER Destination
    Specifies the pathname of the output file or SQL database where the counters will be written. Defaults to the same directory as the source.

    .PARAMETER Type
    The output format. Defaults to tsv. Options include tsv, csv, bin, and sql.

    For a SQL database, the output file specifies the DSN!counter_log. You can specify the database location by using the ODBC manager to configure the DSN (Database System Name).

    For more information, read here: https://technet.microsoft.com/en-us/library/bb490958.aspx

    .PARAMETER Append
    Appends output file instead of overwriting. This option does not apply to SQL format where the default is always to append.

    .PARAMETER AllowClobber
    Ovewrites the destination file if it exists

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
    Displays the performance counters and time ranges of log files specified in the input file.

    .PARAMETER Raw
    Output the results of the DOS command instead of Get-ChildItem
    
    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Invoke-DbaPfRelog

    .EXAMPLE
    Invoke-DbaPfRelog -Path C:\temp\perfmon.blg -Destination C:\temp\a\b\c

    Creats the temp, a, and b directories if needed, then generates c.tsv (tab separated) from C:\temp\perfmon.blg
    
    Returns the newly created file as a file object
    
    .EXAMPLE
    Invoke-DbaPfRelog -Path C:\temp\perfmon.blg -Destination C:\temp\a\b\c -Raw

    Creats the temp, a, and b directories if needed, then generates c.tsv (tab separated) from C:\temp\perfmon.blg then outputs the raw results of the relog command.
    
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

    .EXAMPLE
    Invoke-DbaPfRelog -Path 'C:\temp\perflog with spaces.blg' -Destination C:\temp\a\b\c -Type csv -BeginTime ((Get-Date).AddDays(-30)) -EndTime ((Get-Date).AddDays(-1))
    
    Creates the temp, a, and b directories if needed, then generates c.csv (comma separated) from C:\temp\perflog with spaces.blg', starts 30 day ago and ends one day ago

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
        [switch]$Raw,
        [switch]$EnableException
    )
    begin {
        if (Test-Bound -ParameterName BeginTime) {
            $beginstring = ($BeginTime -f 'M/d/yyyy hh:mm:ss' | Out-String).Trim()
        }
        if (Test-Bound -ParameterName EndTime) {
            $endstring = ($EndTime -f 'M/d/yyyy hh:mm:ss' | Out-String).Trim()
        }
    }
    process {
        if ($Append -and $Type -ne "bin") {
            Stop-Function -Message "Append can only be used with -Type bin" -Target $file
            return
        }
        
        if ($InputObject) {
            # DataCollectorSet
            if ($InputObject.OutputLocation -and $InputObject.RemoteOutputLocation) {
                $instance = [dbainstance]$InputObject.ComputerName
                
                if ($instance.IsLocalHost) {
                    $Path += (Get-ChildItem -Recurse -Path $InputObject.OutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                }
                else {
                    $Path += (Get-ChildItem -Recurse -Path $InputObject.RemoteOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                }
            }
            # DataCollector
            if ($InputObject.LatestOutputLocation -and $InputObject.RemoteLatestOutputLocation) {
                $instance = [dbainstance]$InputObject.ComputerName
                
                if ($instance.IsLocalHost) {
                    $Path += (Get-ChildItem -Recurse -Path $InputObject.LatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                }
                else {
                    $Path += (Get-ChildItem -Recurse -Path $InputObject.RemoteLatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                }
            }
        }
        
        $Path = $Path | Where-Object { $_ -match '.blg' }
        
        foreach ($file in $Path) {
            
            $item = Get-ChildItem -Path $file -ErrorAction SilentlyContinue
            
            if ($item -eq $null) {
                Stop-Function -Message "$file does not exist" -Target $file
                return
            }
            
            if ((Test-Bound -ParameterName Destination -Not) -and -not $Append) {
                $Destination = Join-Path (Split-Path $Path) $item.BaseName
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
            
            if ($beginstring) {
                $params += "-b $beginstring"
            }
            
            if ($endstring) {
                $params += "-e $endstring"
            }
            
            if ($ConfigPath) {
                $params += "-config $ConfigPath"
            }
            
            if ($Summary) {
                $params += "-q"
            }
            
        }
        
        if (-not ($Destination.StartsWith("DSN"))) {
            $outputisfile = $true
        }
        else {
            $outputisfile = $false
        }
        
        if ($outputisfile) {
            if ($Destination) {
                $dir = Split-Path $Destination
                if (-not (Test-Path -Path $dir)) {
                    try {
                        $null = New-Item -ItemType Directory -Path $dir -ErrorAction Stop
                    }
                    catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $Destination
                    }
                }
                
                if ((Test-Path $Destination) -and -not $Append -and ((Get-Item $Destination) -isnot [System.IO.DirectoryInfo])) {
                    if ($AllowClobber) {
                        try {
                            Remove-Item -Path "$Destination" -ErrorAction Stop
                        }
                        catch {
                            Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                        }
                    }
                    else {
                        if ($Type -eq "bin") {
                            Stop-Function -Message "$Destination exists. Use -AllowClobber to overwrite or -Append to append." -Continue
                        }
                        else {
                            Stop-Function -Message "$Destination exists. Use -AllowClobber to overwrite." -Continue
                        }
                    }
                }
                
                if ((Test-Path "$Destination.$type") -and -not $Append) {
                    if ($AllowClobber) {
                        try {
                            Remove-Item -Path "$Destination.$type" -ErrorAction Stop
                        }
                        catch {
                            Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                        }
                    }
                    else {
                        if ($Type -eq "bin") {
                            Stop-Function -Message "$("$Destination.$type") exists. Use -AllowClobber to overwrite or -Append to append." -Continue
                        }
                        else {
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
            }
            else {
                Write-Message -Level Verbose -Message "relog $arguments"
                $output = (cmd /c "relog $arguments" | Out-String).Trim()
                
                if ($output -match "Error") {
                    Stop-Function -Continue -Message "relog $arguments`n$output"
                }
                else {
                    Write-Message -Level Verbose -Message $output
                    $array = $output -Split [environment]::NewLine
                    $files = $array | Select-String "File:"
                    
                    foreach ($file in $files) {
                        $file = $file.ToString().Replace("File:","").Trim()
                        Get-ChildItem $file
                    }
                }
            }
        }
        catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $path
        }
    }
}
function Invoke-DbaRelog {
 <#
    .SYNOPSIS
    Pipable wrapper for the relog command which is available on modern Windows platforms.

    .DESCRIPTION
    Pipable wrapper for the relog command. Relog is useful for converting Windows Perfmon.

    Extracts performance counters from performance counter logs into other formats,
    such as text-TSV (for tab-delimited text), text-CSV (for comma-delimited text), binary-BIN, or SQL.

    relog "C:\PerfLogs\Admin\System Correlation\WORKSTATIONX_20180112-000001\DataCollector01.blg" -o C:\temp\foo.csv -f tsv

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

    .PARAMETER PerformanceCounter
    Specifies the performance counter path to log.

    .PARAMETER PerformanceCounterPath
    Specifies the pathname of the text file that lists the performance counters to be included in a relog file. Use this option to list counter paths in an input file, one per line. Default setting is all counters in the original log file are relogged.

    .PARAMETER Interval
    Specifies sample intervals in "n" records. Includes every nth data point in the relog file. Default is every data point.

    .PARAMETER BeginTime
    Date and time must be in this exact format M/d/yyyy hh:mm:ss.

    .PARAMETER EndTime
    Specifies end time for copying last record from the input file. Date and time must be in this exact format M/d/yyyy hh:mm:ss.

    .PARAMETER ConfigPath
    Specifies the pathname of the settings file that contains command-line parameters.

    .PARAMETER Summary
    Displays the performance counters and time ranges of log files specified in the input file.

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Invoke-DbaRelog

    .EXAMPLE
    Invoke-DbaRelog -Path C:\temp\perfmon.blg -Destination C:\temp\a\b\c

    Creats the temp, a, and b directories if needed, then generates c.tsv (tab separated) from C:\temp\perfmon.blg
    
    [Invoke-DbaRelog][21:21:35] relog "C:\temp\perfmon.blg" -f csv -o C:\temp\a\b\c

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
    Invoke-DbaRelog -Path 'C:\temp\perflog with spaces.blg' -Destination C:\temp\a\b\c -Type csv
    
    Creates the temp, a, and b directories if needed, then generates c.csv (comma separated) from C:\temp\perflog with spaces.blg'

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
        [string[]]$PerformanceCounter,
        [string]$PerformanceCounterPath,
        [int]$Interval,
        [string]$BeginTime,
        [string]$EndTime,
        [string]$ConfigPath,
        [switch]$Summary,
        [switch]$EnableException
    )
    process {
        foreach ($file in $Path) {

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
                $params += "-o $Destination"
            }

            if ($BeginTime) {
                $params += "-b $BeginTime"
            }

            if ($EndTime) {
                $params += "-e $EndTime"
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

        if ($outputisfile -and $Destination) {
            if (-not (Test-Path -Path $Destination)) {
                try {
                    $null = New-Item -ItemType Directory -Path $Destination -ErrorAction Stop
                }
                catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $Destination
                }
            }
        }
        
        try {
            $arguments = ($params -join " ")
            Write-Message -Level Output -Message "relog $arguments"
            cmd /c "relog $arguments"
        }
        catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $path
        }
    }
}
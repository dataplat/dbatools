function Get-DbaPfDataCollector {
    <#
    .SYNOPSIS
        Retrieves Windows Performance Monitor data collectors and their configuration details from local or remote computers.

    .DESCRIPTION
        Retrieves detailed information about Windows Performance Monitor data collectors within collector sets, commonly used by DBAs to monitor SQL Server performance counters. This function parses the XML configuration of existing data collectors to show their settings, file locations, sample intervals, and the specific performance counters they collect.

        Use this when you need to audit existing performance monitoring setups, verify collector configurations, or identify which performance counters are being captured for SQL Server baseline analysis and troubleshooting. The function works across multiple computers and integrates with Get-DbaPfDataCollectorSet for filtering specific collector sets.

    .PARAMETER ComputerName
        Specifies the target computer(s) to retrieve performance data collectors from. Defaults to localhost.
        Use this to monitor performance collectors across multiple SQL Server environments or remote systems where SQL Server performance monitoring is configured.

    .PARAMETER Credential
        Allows you to login to servers using alternative credentials. To use:

        $scred = Get-Credential, then pass $scred object to the -Credential parameter.

    .PARAMETER CollectorSet
        Filters results to data collectors within specific collector sets by name. Accepts wildcards for pattern matching.
        Use this when you want to examine collectors in a particular performance monitoring setup, such as 'System Correlation' or custom SQL Server baseline collector sets.

    .PARAMETER Collector
        Filters results to specific data collectors by name within the collector sets. Accepts wildcards for pattern matching.
        Use this when you need to examine a particular collector's configuration, such as one focused on SQL Server counters or system resource monitoring.

    .PARAMETER InputObject
        Accepts collector set objects from Get-DbaPfDataCollectorSet via the pipeline to retrieve their individual data collectors.
        Use this for pipeline operations when you want to drill down from collector sets to examine the specific performance counters and configuration details of their data collectors.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Performance, DataCollector, PerfCounter
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaPfDataCollector

    .OUTPUTS
        PSCustomObject

        Returns one object per data collector found within the specified collector sets. Each object represents a single Performance Monitor data collector configuration.

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer where the collector set is configured
        - DataCollectorSet: The name of the parent data collector set containing this collector
        - Name: The logical name of the data collector within the collector set
        - DataCollectorType: The type of data collector (e.g., PerformanceCounterDataCollector)
        - DataSourceName: The name of the performance counter data source being collected
        - FileName: The base file name where performance counter data is written
        - FileNameFormat: Format specification for the output file naming (e.g., monddyy)
        - FileNameFormatPattern: The file naming pattern used for sequential file naming
        - LatestOutputLocation: The full path where the most recent collector output is stored
        - LogAppend: Boolean indicating if new data is appended to existing log files
        - LogCircular: Boolean indicating if the log uses circular buffering (overwrites when full)
        - LogFileFormat: The format of the log file (e.g., csv, binary, sql)
        - LogOverwrite: Boolean indicating if existing log data is overwritten
        - SampleInterval: The sampling interval in milliseconds between performance counter samples
        - SegmentMaxRecords: The maximum number of records per log segment
        - Counters: The collection of performance counters being collected by this collector

        Additional properties available (not shown by default):
        - CounterDisplayNames: Display names for the performance counters
        - RemoteLatestOutputLocation: UNC path for accessing the latest output location remotely
        - DataCollectorSetXml: The raw XML configuration of the parent data collector set
        - CollectorXml: The raw XML configuration of this specific data collector
        - DataCollectorObject: Flag indicating this is a data collector object
        - Credential: The credential object used for remote access (if applicable)

        Use Select-Object * to access all properties available in the object.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollector

        Gets all Collectors on localhost.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollector -ComputerName sql2017

        Gets all Collectors on sql2017.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollector -ComputerName sql2017, sql2016 -Credential ad\sqldba -CollectorSet 'System Correlation'

        Gets all Collectors for the 'System Correlation' CollectorSet on sql2017 and sql2016 using alternative credentials.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSet -CollectorSet 'System Correlation' | Get-DbaPfDataCollector

        Gets all Collectors for the 'System Correlation' CollectorSet.

    #>
    [CmdletBinding()]
    param (
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Alias("DataCollectorSet")]
        [string[]]$CollectorSet,
        [Alias("DataCollector")]
        [string[]]$Collector,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $columns = 'ComputerName', 'DataCollectorSet', 'Name', 'DataCollectorType', 'DataSourceName', 'FileName', 'FileNameFormat', 'FileNameFormatPattern', 'LatestOutputLocation', 'LogAppend', 'LogCircular', 'LogFileFormat', 'LogOverwrite', 'SampleInterval', 'SegmentMaxRecords', 'Counters'
    }
    process {


        if ($InputObject.Credential -and (Test-Bound -ParameterName Credential -Not)) {
            $Credential = $InputObject.Credential
        }

        if (-not $InputObject -or ($InputObject -and (Test-Bound -ParameterName ComputerName))) {
            foreach ($computer in $ComputerName) {
                $InputObject += Get-DbaPfDataCollectorSet -ComputerName $computer -Credential $Credential -CollectorSet $CollectorSet
            }
        }

        if ($InputObject) {
            if (-not $InputObject.DataCollectorSetObject) {
                Stop-Function -Message "InputObject is not of the right type. Please use Get-DbaPfDataCollectorSet."
                return
            }
        }

        foreach ($set in $InputObject) {
            $collectorxml = ([xml]$set.Xml).DataCollectorSet.PerformanceCounterDataCollector
            foreach ($col in $collectorxml) {
                if ($Collector -and $Collector -notcontains $col.Name) {
                    continue
                }

                $outputlocation = $col.LatestOutputLocation
                if ($outputlocation) {
                    $dir = ($outputlocation).Replace(':', '$')
                    $remote = "\\$($set.ComputerName)\$dir"
                } else {
                    $remote = $null
                }

                [PSCustomObject]@{
                    ComputerName               = $set.ComputerName
                    DataCollectorSet           = $set.Name
                    Name                       = $col.Name
                    FileName                   = $col.FileName
                    DataCollectorType          = $col.DataCollectorType
                    FileNameFormat             = $col.FileNameFormat
                    FileNameFormatPattern      = $col.FileNameFormatPattern
                    LogAppend                  = $col.LogAppend
                    LogCircular                = $col.LogCircular
                    LogOverwrite               = $col.LogOverwrite
                    LatestOutputLocation       = $col.LatestOutputLocation
                    DataCollectorSetXml        = $set.Xml
                    RemoteLatestOutputLocation = $remote
                    DataSourceName             = $col.DataSourceName
                    SampleInterval             = $col.SampleInterval
                    SegmentMaxRecords          = $col.SegmentMaxRecords
                    LogFileFormat              = $col.LogFileFormat
                    Counters                   = $col.Counter
                    CounterDisplayNames        = $col.CounterDisplayName
                    CollectorXml               = $col
                    DataCollectorObject        = $true
                    Credential                 = $Credential
                } | Select-DefaultView -Property $columns
            }
        }
    }
}
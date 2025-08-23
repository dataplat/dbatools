function Get-DbaPfDataCollectorCounterSample {
    <#
    .SYNOPSIS
        Retrieves real-time performance counter samples from SQL Server systems for monitoring and troubleshooting.

    .DESCRIPTION
        Collects performance counter data from Windows Performance Monitor collector sets and individual counters on SQL Server systems. This function wraps PowerShell's Get-Counter cmdlet to provide structured performance data that DBAs use for monitoring CPU, memory, disk I/O, and SQL Server-specific metrics. You can capture single snapshots for quick checks or continuous samples for ongoing monitoring during troubleshooting sessions. The output integrates seamlessly with Get-DbaPfDataCollectorCounter to build comprehensive performance monitoring workflows.

    .PARAMETER ComputerName
        The target computer where performance counters will be collected. Defaults to localhost.
        Use this when monitoring remote SQL Server systems or collecting performance data from multiple servers simultaneously.

    .PARAMETER Credential
        Allows you to login to servers using alternative credentials. To use:

        $scred = Get-Credential, then pass $scred object to the -Credential parameter.

    .PARAMETER CollectorSet
        Specifies which Performance Monitor Data Collector Set to sample counters from. Accepts wildcard patterns for matching multiple sets.
        Use this to focus on specific pre-configured collector sets like 'System Performance' or custom SQL Server monitoring sets instead of sampling all available counters.

    .PARAMETER Collector
        Specifies which individual Data Collector within a Collector Set to sample from. Accepts wildcard patterns.
        Use this when you need samples from specific collectors rather than all collectors in a set, such as targeting only SQL Server-related collectors.

    .PARAMETER Counter
        Specifies individual performance counter paths to sample in the standard format like '\Processor(_Total)\% Processor Time' or '\SQLServer:Buffer Manager\Page life expectancy'.
        Use this when you need specific counters for targeted troubleshooting rather than sampling all available counters from collector sets.

    .PARAMETER Continuous
        Enables continuous sampling until you press CTRL+C instead of taking a single snapshot. Combine with SampleInterval to control timing between samples.
        Use this during active troubleshooting sessions when you need to monitor performance trends in real-time, such as during query execution or system load events.

    .PARAMETER ListSet
        Lists available performance counter sets on the target computers without collecting samples. Supports wildcard patterns for filtering.
        Use this to discover what counter sets are available before running collection commands, especially useful when working with unfamiliar systems or custom monitoring configurations.

    .PARAMETER MaxSamples
        Specifies the maximum number of samples to collect from each counter before stopping. Default is 1 sample.
        Use this when you need a specific number of data points for analysis, such as collecting 60 samples at 1-second intervals to get one minute of baseline performance data.

    .PARAMETER SampleInterval
        Sets the time interval between samples in seconds with a minimum and default of 1 second.
        Use this to control sampling frequency based on your monitoring needs - shorter intervals for active troubleshooting or longer intervals for baseline collection to reduce overhead.

    .PARAMETER InputObject
        Accepts the object output by Get-DbaPfDataCollectorCounter via the pipeline.

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
        https://dbatools.io/Get-DbaPfDataCollectorCounterSample

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorCounterSample

        Gets a single sample for all counters for all Collector Sets on localhost.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorCounterSample -Counter '\Processor(_Total)\% Processor Time'

        Gets a single sample for all counters for all Collector Sets on localhost.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorCounter -ComputerName sql2017, sql2016 | Out-GridView -PassThru | Get-DbaPfDataCollectorCounterSample -MaxSamples 10

        Gets 10 samples for all counters for all Collector Sets for servers sql2016 and sql2017.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorCounterSample -ComputerName sql2017

        Gets a single sample for all counters for all Collector Sets on sql2017.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorCounterSample -ComputerName sql2017, sql2016 -Credential ad\sqldba -CollectorSet 'System Correlation'

        Gets a single sample for all counters for the 'System Correlation' CollectorSet on sql2017 and sql2016 using alternative credentials.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorCounterSample -CollectorSet 'System Correlation'

        Gets a single sample for all counters for the 'System Correlation' CollectorSet.

    #>
    [CmdletBinding()]
    param (
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Alias("DataCollectorSet")]
        [string[]]$CollectorSet,
        [Alias("DataCollector")]
        [string[]]$Collector,
        [string[]]$Counter,
        [switch]$Continuous,
        [switch[]]$ListSet,
        [int]$MaxSamples,
        [int]$SampleInterval,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    process {


        if ($InputObject.Credential -and (Test-Bound -ParameterName Credential -Not)) {
            $Credential = $InputObject.Credential
        }

        if ($InputObject.Counter -and (Test-Bound -ParameterName Counter -Not)) {
            $Counter = $InputObject.Counter
        }

        if (-not $InputObject -or ($InputObject -and (Test-Bound -ParameterName ComputerName))) {
            foreach ($computer in $ComputerName) {
                $InputObject += Get-DbaPfDataCollectorCounter -ComputerName $computer -Credential $Credential -CollectorSet $CollectorSet -Collector $Collector
            }
        }

        if ($InputObject) {
            if (-not $InputObject.CounterObject) {
                Stop-Function -Message "InputObject is not of the right type. Please use Get-DbaPfDataCollectorCounter."
                return
            }
        }

        foreach ($counterobject in $InputObject) {
            if ((Test-Bound -ParameterName Counter) -and ($Counter -notcontains $counterobject.Name)) { continue }
            $params = @{
                Counter = $counterobject.Name
            }

            if (-not ([dbainstance]$counterobject.ComputerName).IsLocalHost) {
                $params.Add("ComputerName", $counterobject.ComputerName)
            }

            if ($Credential) {
                $params.Add("Credential", $Credential)
            }

            if ($Continuous) {
                $params.Add("Continuous", $Continuous)
            }

            if ($ListSet) {
                $params.Add("ListSet", $ListSet)
            }

            if ($MaxSamples) {
                $params.Add("MaxSamples", $MaxSamples)
            }

            if ($SampleInterval) {
                $params.Add("SampleInterval", $SampleInterval)
            }

            if ($Continuous) {
                Get-Counter @params
            } else {
                try {
                    $pscounters = Get-Counter @params -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Failure for $($counterobject.Name) on $($counterobject.ComputerName)." -ErrorRecord $_ -Continue
                }

                foreach ($pscounter in $pscounters) {
                    foreach ($sample in $pscounter.CounterSamples) {
                        [PSCustomObject]@{
                            ComputerName           = $counterobject.ComputerName
                            DataCollectorSet       = $counterobject.DataCollectorSet
                            DataCollector          = $counterobject.DataCollector
                            Name                   = $counterobject.Name
                            Timestamp              = $pscounter.Timestamp
                            Path                   = $sample.Path
                            InstanceName           = $sample.InstanceName
                            CookedValue            = $sample.CookedValue
                            RawValue               = $sample.RawValue
                            SecondValue            = $sample.SecondValue
                            MultipleCount          = $sample.MultipleCount
                            CounterType            = $sample.CounterType
                            SampleTimestamp        = $sample.Timestamp
                            SampleTimestamp100NSec = $sample.Timestamp100NSec
                            Status                 = $sample.Status
                            DefaultScale           = $sample.DefaultScale
                            TimeBase               = $sample.TimeBase
                            Sample                 = $pscounter.CounterSamples
                            CounterSampleObject    = $true
                        } | Select-DefaultView -ExcludeProperty Sample, CounterSampleObject
                    }
                }
            }
        }
    }
}
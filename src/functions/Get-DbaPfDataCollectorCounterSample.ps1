function Get-DbaPfDataCollectorCounterSample {
    <#
    .SYNOPSIS
        Gets Performance Counter Samples.

    .DESCRIPTION
        Gets Performance Counter Samples.

    .PARAMETER ComputerName
        The target computer. Defaults to localhost.

    .PARAMETER Credential
        Allows you to login to servers using alternative credentials. To use:

        $scred = Get-Credential, then pass $scred object to the -Credential parameter.

    .PARAMETER CollectorSet
        The Collector Set name.

    .PARAMETER Collector
        The Collector name.

    .PARAMETER Counter
        The Counter name. This must be in the form of '\Processor(_Total)\% Processor Time'.

    .PARAMETER Continuous
        If this switch is enabled, samples will be retrieved continuously until you press CTRL+C. By default, this command gets only one counter sample. You can use the SampleInterval parameter to set the interval for continuous sampling.

    .PARAMETER ListSet
        Gets the specified performance counter sets on the computers. Enter the names of the counter sets. Wildcards are permitted.

    .PARAMETER MaxSamples
        Specifies the number of samples to get from each counter. The default is 1 sample. To get samples continuously (no maximum sample size), use the Continuous parameter.

        To collect a very large data set, consider running a Get-DbaPfDataCollectorCounterSample command as a Windows PowerShell background job.

    .PARAMETER SampleInterval
        Specifies the time between samples in seconds. The minimum value and the default value are 1 second.

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
                        [pscustomobject]@{
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
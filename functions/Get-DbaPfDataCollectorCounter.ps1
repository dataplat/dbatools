function Get-DbaPfDataCollectorCounter {
    <#
    .SYNOPSIS
        Gets Performance Counters.

    .DESCRIPTION
        Gets Performance Counters.

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
        The Counter name to capture. This must be in the form of '\Processor(_Total)\% Processor Time'.

    .PARAMETER InputObject
        Accepts the object output by Get-DbaPfDataCollectorSet via the pipeline.

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
        https://dbatools.io/Get-DbaPfDataCollectorCounter

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorCounter

        Gets all counters for all Collector Sets on localhost.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorCounter -ComputerName sql2017

        Gets all counters for all Collector Sets on  on sql2017.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorCounter -ComputerName sql2017 -Counter '\Processor(_Total)\% Processor Time'

        Gets the '\Processor(_Total)\% Processor Time' counter on sql2017.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorCounter -ComputerName sql2017, sql2016 -Credential ad\sqldba -CollectorSet 'System Correlation'

        Gets all counters for the 'System Correlation' CollectorSet on sql2017 and sql2016 using alternative credentials.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSet -CollectorSet 'System Correlation' | Get-DbaPfDataCollector | Get-DbaPfDataCollectorCounter

        Gets all counters for the 'System Correlation' CollectorSet.

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
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        #Variable marked as unused by PSScriptAnalyzer
        #$columns = 'ComputerName', 'Name', 'DataCollectorSet', 'Counters', 'DataCollectorType', 'DataSourceName', 'FileName', 'FileNameFormat', 'FileNameFormatPattern', 'LatestOutputLocation', 'LogAppend', 'LogCircular', 'LogFileFormat', 'LogOverwrite', 'SampleInterval', 'SegmentMaxRecords'
    }
    process {


        if ($InputObject.Credential -and (Test-Bound -ParameterName Credential -Not)) {
            $Credential = $InputObject.Credential
        }

        if (-not $InputObject -or ($InputObject -and (Test-Bound -ParameterName ComputerName))) {
            foreach ($computer in $ComputerName) {
                $InputObject += Get-DbaPfDataCollector -ComputerName $computer -Credential $Credential -CollectorSet $CollectorSet -Collector $Collector
            }
        }

        if ($InputObject) {
            if (-not $InputObject.DataCollectorObject) {
                Stop-Function -Message "InputObject is not of the right type. Please use Get-DbaPfDataCollector."
                return
            }
        }

        foreach ($counterobject in $InputObject) {
            foreach ($countername in $counterobject.Counters) {
                if ($Counter -and $Counter -notcontains $countername) { continue }
                [pscustomobject]@{
                    ComputerName        = $counterobject.ComputerName
                    DataCollectorSet    = $counterobject.DataCollectorSet
                    DataCollector       = $counterobject.Name
                    DataCollectorSetXml = $counterobject.DataCollectorSetXml
                    Name                = $countername
                    FileName            = $counterobject.FileName
                    CounterObject       = $true
                    Credential          = $Credential
                } | Select-DefaultView -ExcludeProperty DataCollectorObject, Credential, CounterObject, DataCollectorSetXml
            }
        }
    }
}
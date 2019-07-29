function Get-DbaPfDataCollector {
    <#
    .SYNOPSIS
        Gets Performance Monitor Data Collectors.

    .DESCRIPTION
        Gets Performance Monitor Data Collectors.

    .PARAMETER ComputerName
        The target computer. Defaults to localhost.

    .PARAMETER Credential
        Allows you to login to servers using alternative credentials. To use:

        $scred = Get-Credential, then pass $scred object to the -Credential parameter.

    .PARAMETER CollectorSet
        The Collector Set name.

    .PARAMETER Collector
        The Collector name.

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
        https://dbatools.io/Get-DbaPfDataCollector

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

                [pscustomobject]@{
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
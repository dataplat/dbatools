function Get-DbaPfDataCollectorCounter {
    <#
    .SYNOPSIS
        Retrieves performance counter configurations from Windows Performance Monitor Data Collector Sets.

    .DESCRIPTION
        Retrieves the list of performance counters that are configured within Windows Performance Monitor Data Collector Sets. This is useful for auditing performance monitoring configurations, verifying which SQL Server and system counters are being collected, and understanding your performance data collection setup. The function extracts counter details from existing Data Collector objects, showing you exactly which performance metrics are being tracked for troubleshooting and capacity planning.

    .PARAMETER ComputerName
        Specifies the target server(s) where Performance Monitor Data Collector Sets are configured.
        Use this to audit performance counters on remote SQL Server instances or retrieve counter configurations from multiple servers at once.

    .PARAMETER Credential
        Allows you to login to servers using alternative credentials. To use:

        $scred = Get-Credential, then pass $scred object to the -Credential parameter.

    .PARAMETER CollectorSet
        Filters results to specific Data Collector Set names such as 'System Correlation' or custom SQL performance monitoring sets.
        Use this when you need to examine counters for particular monitoring scenarios rather than reviewing all configured performance data collection.

    .PARAMETER Collector
        Filters results to specific Data Collector names within a Collector Set.
        Use this to narrow down results when a Collector Set contains multiple data collectors and you only need counter details from specific ones.

    .PARAMETER Counter
        Searches for specific performance counter names using the exact Windows Performance Monitor format like '\SQLServer:Buffer Manager\Page life expectancy' or '\Processor(_Total)\% Processor Time'.
        Use this to verify if critical SQL Server or system performance counters are being monitored in your data collection setup.

    .PARAMETER InputObject
        Accepts Data Collector objects from Get-DbaPfDataCollector via the pipeline to extract counter configurations.
        Use this for chaining commands when you want to drill down from Collector Sets to specific Data Collectors and then to their individual performance counters.

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

    .OUTPUTS
        PSCustomObject

        Returns one object per counter added to the Data Collector Set.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - DataCollectorSet: The name of the parent Data Collector Set containing the collector
        - DataCollector: The name of the specific Data Collector within the Collector Set
        - Name: The full path of the performance counter (e.g., '\Processor(_Total)\% Processor Time')
        - FileName: The output file name where performance counter data will be stored

        Additional properties available:
        - DataCollectorSetXml: XML configuration of the Data Collector Set
        - Credential: The credential object used for authentication

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
                [PSCustomObject]@{
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
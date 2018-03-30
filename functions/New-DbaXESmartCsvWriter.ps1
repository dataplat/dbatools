function New-DbaXESmartCsvWriter {
    <#
        .SYNOPSIS
            This Response type is used to write Extended Events to a CSV file.

        .DESCRIPTION
            This Response type is used to write Extended Events to a CSV file.

        .PARAMETER OutputFile
            Specifies the path to the output CSV file.

        .PARAMETER Overwrite
            Specifies whether any existiting file should be overwritten or not.

        .PARAMETER OutputColumn
            Specifies the list of columns to output from the events. XESmartTarget will capture in memory and write to the target table only the columns (fields or targets) that are present in this list.

            Fields and actions are matched in a case-sensitive manner.

            Expression columns are supported. Specify a column with ColumnName AS Expression to add an expression column (Example: Total AS Reads + Writes)

        .PARAMETER Event
            Specifies a list of events to be processed (with others being ignored. By default, all events are processed.

        .PARAMETER Filter
            Specifies a filter expression in the same form as you would use in the WHERE clause of a SQL query.

            Example: duration > 10000 AND cpu_time > 10000

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: ExtendedEvent, XE, Xevent
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT
            SmartTarget: by Gianluca Sartori (@spaghettidba)

        .LINK
            https://dbatools.io/New-DbaXESmartCsvWriter
            https://github.com/spaghettidba/XESmartTarget/wiki

        .EXAMPLE
            $columns = "cpu_time", "duration", "physical_reads", "logical_reads", "writes", "row_count"
            $response = New-DbaXESmartCsvWriter -OutputFile c:\temp\workload.csv -OutputColumn $columns -OverWrite -Event "sql_batch_completed"
            Start-DbaXESmartTarget -SqlInstance localhost\sql2017 -Session "Profiler Standard" -Responder $response

            Writes Extended Events to the file "C:\temp\workload.csv".
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [string]$OutputFile,
        [switch]$Overwrite,
        [string[]]$Event,
        [string[]]$OutputColumn,
        [string]$Filter,
        [switch]$EnableException
    )

    begin {
        try {
            Add-Type -Path "$script:PSModuleRoot\bin\XESmartTarget\XESmartTarget.Core.dll" -ErrorAction Stop
        }
        catch {
            Stop-Function -Message "Could not load XESmartTarget.Core.dll" -ErrorRecord $_ -Target "XESmartTarget"
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        try {
            $writer = New-Object -TypeName XESmartTarget.Core.Responses.CsvAppenderResponse
            $writer.OutputFile = $OutputFile
            $writer.OverWrite = $Overwrite
            if (Test-Bound -ParameterName "Event") {
                $writer.Events = $Event
            }
            if (Test-Bound -ParameterName "OutputColumn") {
                $writer.OutputColumns = $OutputColumn
            }
            if (Test-Bound -ParameterName "Filter") {
                $writer.Filter = $Filter
            }
            $writer
        }
        catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Target "XESmartTarget" -Continue
        }
    }
}

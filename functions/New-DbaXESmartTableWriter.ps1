function New-DbaXESmartTableWriter {
 <#
    .SYNOPSIS
     This Response type is used to write Extended Events to a database table.

    .DESCRIPTION
    This Response type is used to write Extended Events to a database table. The events are temporarily stored in memory before being written to the database at regular intervals.

    The target table can be created manually upfront or you can let the TableAppenderResponse create a target table based on the fields and actions available in the events captured.
    The columns of the target table and the fields/actions of the events are mapped by name (case-sensitive).

    .PARAMETER SqlInstance
    The SQL Instances that you're connecting to.

    .PARAMETER SqlCredential
    Credential object used to connect to the SQL Server as a different user

    .PARAMETER Database
    Specifies the name of the database that contains the target table.

    .PARAMETER Table
    Specifies the name of the target table.

    .PARAMETER AutoCreateTargetTable
    When true, XESmartTarget will infer the definition of the target table from the columns captured in the Extended Events session.

    If the target table already exists, it will not be recreated.

    .PARAMETER UploadIntervalSeconds
    Specifies the number of seconds XESmartTarget will keep the events in memory befory dumping them to the target table. The default is 10 seconds.

    .PARAMETER OutputColumns
    Specifies the list of columns to output from the events. XESmartTarget will capture in memory and write to the target table only the columns (fields or targets) that are present in this list.

    Fields and actions are matched in a case-sensitive manner.

    Expression columns are supported too: specify a column with ColumnName AS Expression to add an expression column (Example: Total AS Reads + Writes)

    .PARAMETER Events
    Each Response can be limited to processing specific events, while ignoring all the other ones. When this attribute is omitted, all events are processed.

    .PARAMETER Filter
    You can specify a filter expression by using this attribute. The filter expression is in the same form that you would use in a SQL query.

    For example, a valid example looks like this: duration > 10000 AND cpu_time > 10000

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
    SmartTarget: by Gianluca Sartori (@spaghettidba)

    .LINK
    https://dbatools.io/New-DbaXESmartTableWriter
    https://github.com/spaghettidba/XESmartTarget/wiki

    .EXAMPLE
    New-DbaXESmartTableWriter

    Coming soon
#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$Database,
        [parameter(Mandatory)]
        [string]$Table,
        [switch]$AutoCreateTargetTable,
        [int]$UploadIntervalSeconds = 10,
        [string[]]$Events,
        [string[]]$OutputColumns = @("cpu_time", "duration", "physical_reads", "logical_reads", "writes", "row_count", "batch_text"),
        [string]$Filter = "duration > 10000",
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

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $writer = New-Object -TypeName XESmartTarget.Core.Responses.TableAppenderResponse
                $writer.ServerName = $server.Name
                $writer.DatabaseName = $Database
                $writer.TableName = $Table
                $writer.AutoCreateTargetTable = $AutoCreateTargetTable
                $writer.UploadIntervalSeconds = $UploadIntervalSeconds
                $writer.Events = $Events
                $writer.OutputColumns = $OutputColumns
                $writer.Filter = $Filter
                $writer
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target "XESmartTarget" -Continue
            }
        }
    }
}
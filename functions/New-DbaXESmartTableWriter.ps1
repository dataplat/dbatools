function New-DbaXESmartTableWriter {
    <#
        .SYNOPSIS
            This Response type is used to write Extended Events to a database table.

        .DESCRIPTION
            This Response type is used to write Extended Events to a database table. The events are temporarily stored in memory before being written to the database at regular intervals.

            The target table can be created manually upfront or you can let the TableAppenderResponse create a target table based on the fields and actions available in the events captured.

            The columns of the target table and the fields/actions of the events are mapped by name (case-sensitive).

       .PARAMETER SqlInstance
            Target SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Database
            Specifies the name of the database that contains the target table.

        .PARAMETER Table
            Specifies the name of the target table.

        .PARAMETER AutoCreateTargetTable
            If this switch is enabled, XESmartTarget will infer the definition of the target table from the columns captured in the Extended Events session.

            If the target table already exists, it will not be recreated.

        .PARAMETER UploadIntervalSeconds
            Specifies the number of seconds XESmartTarget will keep the events in memory before dumping them to the target table. The default is 10 seconds.

        .PARAMETER OutputColumns
            Specifies the list of columns to output from the events. XESmartTarget will capture in memory and write to the target table only the columns (fields or targets) that are present in this list.

            Fields and actions are matched in a case-sensitive manner.

            Expression columns are supported. Specify a column with ColumnName AS Expression to add an expression column (Example: Total AS Reads + Writes)

        .PARAMETER Events
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
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
            SmartTarget: by Gianluca Sartori (@spaghettidba)

        .LINK
            https://dbatools.io/New-DbaXESmartTableWriter
            https://github.com/spaghettidba/XESmartTarget/wiki

        .EXAMPLE
            $columns = "cpu_time", "duration", "physical_reads", "logical_reads", "writes", "row_count", "batch_text"
            $response = New-DbaXESmartTableWriter -SqlInstance sql2017 -Database dbadb -Table deadlocktracker -OutputColumns $columns -Filter "duration > 10000"
            Start-DbaXESmartTarget -SqlInstance sql2017 -Session deadlock_tracker -Responder $response
            
            Writes Extended Events to the deadlocktracker table in dbadb on sql2017.
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
        [string[]]$OutputColumns,
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

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
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
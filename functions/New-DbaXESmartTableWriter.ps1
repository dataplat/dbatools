function New-DbaXESmartTableWriter {
    <#
    .SYNOPSIS
        This response type is used to write Extended Events to a database table.

    .DESCRIPTION
        This response type is used to write Extended Events to a database table. The events are temporarily stored in memory before being written to the database at regular intervals.

        The target table can be created manually upfront or you can let the TableAppenderResponse create a target table based on the fields and actions available in the events captured.

        The columns of the target table and the fields/actions of the events are mapped by name (case-sensitive).

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the name of the database that contains the target table.

    .PARAMETER Table
        Specifies the name of the target table.

    .PARAMETER AutoCreateTargetTable
        If this switch is enabled, XESmartTarget will infer the definition of the target table from the columns captured in the Extended Events session.

        If the target table already exists, it will not be recreated.

    .PARAMETER UploadIntervalSeconds
        Specifies the number of seconds XESmartTarget will keep the events in memory before dumping them to the target table. The default is 10 seconds.

    .PARAMETER OutputColumn
        Specifies the list of columns to output from the events. XESmartTarget will capture in memory and write to the target table only the columns (fields or targets) that are present in this list.

        Fields and actions are matched in a case-sensitive manner.

        Expression columns are supported. Specify a column with ColumnName AS Expression to add an expression column (Example: Total AS Reads + Writes)

    .PARAMETER Event
        Specifies a list of events to be processed (with others being ignored. By default, all events are processed.

    .PARAMETER Filter
        Specifies a filter expression in the same form as you would use in the WHERE clause of a SQL query.

        Example: duration > 10000 AND cpu_time > 10000

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvent, XE, XEvent, SmartTarget
        Author: Chrissy LeMaire (@cl) | SmartTarget by Gianluca Sartori (@spaghettidba)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
        SmartTarget: by Gianluca Sartori (@spaghettidba)

    .LINK
        https://dbatools.io/New-DbaXESmartTableWriter

    .EXAMPLE
        PS C:\> $columns = "cpu_time", "duration", "physical_reads", "logical_reads", "writes", "row_count", "batch_text"
        PS C:\> $response = New-DbaXESmartTableWriter -SqlInstance sql2017 -Database dbadb -Table deadlocktracker -OutputColumn $columns -Filter "duration > 10000"
        PS C:\> Start-DbaXESmartTarget -SqlInstance sql2017 -Session deadlock_tracker -Responder $response

        Writes Extended Events to the deadlocktracker table in dbadb on sql2017.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$Database,
        [parameter(Mandatory)]
        [string]$Table,
        [switch]$AutoCreateTargetTable,
        [int]$UploadIntervalSeconds = 10,
        [string[]]$Event,
        [string[]]$OutputColumn,
        [string]$Filter,
        [switch]$EnableException
    )
    begin {
        try {
            Add-Type -Path "$script:PSModuleRoot\bin\libraries\third-party\XESmartTarget\XESmartTarget.Core.dll" -ErrorAction Stop
        } catch {
            Stop-Function -Message "Could not load XESmartTarget.Core.dll" -ErrorRecord $_ -Target "XESmartTarget"
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            if ($Pscmdlet.ShouldProcess($instance, "Creating new XESmartTableWriter")) {
                try {
                    $writer = New-Object -TypeName XESmartTarget.Core.Responses.TableAppenderResponse
                    $writer.ServerName = $server.Name
                    $writer.DatabaseName = $Database
                    $writer.TableName = $Table
                    $writer.AutoCreateTargetTable = $AutoCreateTargetTable
                    $writer.UploadIntervalSeconds = $UploadIntervalSeconds
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
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target "XESmartTarget" -Continue
                }
            }
        }
    }
}
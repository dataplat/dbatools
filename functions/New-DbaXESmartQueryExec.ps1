function New-DbaXESmartQueryExec {
    <#
        .SYNOPSIS
            This Response type executes a T-SQL command against a target database whenever an event is recorded.

        .DESCRIPTION
            This Response type executes a T-SQL command against a target database whenever an event is recorded.

        .PARAMETER SqlInstance
            Target SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            Specifies the name of the database that contains the target table.

        .PARAMETER Query
            The T-SQL command to execute. This string can contain placeholders for properties taken from the events.

            Placeholders are in the form {PropertyName}, where PropertyName is one of the fields or actions available in the Event object.

        .PARAMETER Event
            Each Response can be limited to processing specific events, while ignoring all the other ones. When this attribute is omitted, all events are processed.

        .PARAMETER Filter
            You can specify a filter expression by using this attribute. The filter expression is in the same form that you would use in a SQL query. For example, a valid example looks like this: duration > 10000 AND cpu_time > 10000
            
        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: ExtendedEvent, XE, Xevent
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/New-DbaXESmartQueryExec
            https://github.com/spaghettidba/XESmartTarget/wiki

        .EXAMPLE
            $response = New-DbaXESmartQueryExec -SqlInstance sql2017 -Database dbadb -Query "update table set whatever = 1"
            Start-DbaXESmartTarget -SqlInstance sql2017 -Session deadlock_tracker -Responder $response
            
            Executes a T-SQL command against dbadb on sql2017 whenever a deadlock event is recorded.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database,
        [string]$Query,
        [switch]$EnableException,
        [string[]]$Event,
        [string]$Filter
    )
    begin {
        try {
            Add-Type -Path "$script:PSModuleRoot\XESmartTarget\XESmartTarget.Core.dll" -ErrorAction Stop
        }
        catch {
            Stop-Function -Message "Could not load XESmartTarget.Core.dll" -ErrorRecord $_ -Target "XESmartTarget"
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $execute = New-Object -TypeName XESmartTarget.Core.Responses.ExecuteTSQLResponse
            $execute.ServerName = $server.Name
            $execute.DatabaseName = $Database
            $execute.TSQL = $Query

            if ($SqlCredential) {
                $execute.UserName = $SqlCredential.UserName
                $execute.Password = $SqlCredential.GetNetworkCredential().Password
            }

            if (Test-Bound -ParameterName "Event") {
                $execute.Events = $Event
            }
            if (Test-Bound -ParameterName "Filter") {
                $execute.Filter = $Filter
            }

            $execute
        }
    }
}

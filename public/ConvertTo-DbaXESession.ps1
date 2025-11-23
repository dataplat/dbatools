function ConvertTo-DbaXESession {
    <#
    .SYNOPSIS
        Converts SQL Server Traces to Extended Events sessions using intelligent column and event mapping.

    .DESCRIPTION
        Converts existing SQL Server Traces to Extended Events sessions by analyzing trace definitions and mapping events, columns, actions, and filters to their Extended Events equivalents. This eliminates the need to manually recreate monitoring configurations when migrating from the deprecated SQL Trace to Extended Events.

        The function uses a comprehensive mapping table that translates trace events like RPC:Completed, SQL:BatchCompleted, and Lock events to their corresponding Extended Events such as rpc_completed, sql_batch_completed, and lock_acquired. It preserves filters and column selections from the original trace, ensuring equivalent monitoring capabilities in the new Extended Events session.

        By default, the function creates and starts the Extended Events session on the target server. Alternatively, you can generate just the T-SQL script for review or manual execution. This is particularly useful for compliance environments where script review is required before deployment.

        T-SQL code by: Jonathan M. Kehayias, SQLskills.com. T-SQL can be found in this module directory and at
        https://www.sqlskills.com/blogs/jonathan/converting-sql-trace-to-extended-events-in-sql-server-2012/

    .PARAMETER InputObject
        Specifies the SQL Server Trace objects to convert to Extended Events sessions. Must be trace objects returned by Get-DbaTrace.
        Use this to convert existing traces from SQL Trace to Extended Events, preserving event mappings and filter configurations.

    .PARAMETER Name
        Specifies the name for the new Extended Events session. If a session with this name already exists, the function automatically appends the trace ID or a random number to avoid conflicts.
        Choose a descriptive name that identifies the monitoring purpose, as this becomes the session name visible in SQL Server Management Studio and sys.server_event_sessions.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER OutputScriptOnly
        Returns the T-SQL CREATE EVENT SESSION script without executing it on the server. Use this when you need to review the generated script before deployment or save it for later execution.
        Particularly useful in compliance environments where all scripts require approval before running against production databases.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Trace, ExtendedEvent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/ConvertTo-DbaXESession

    .EXAMPLE
        PS C:\> Get-DbaTrace -SqlInstance sql2017, sql2012 | Where-Object Id -eq 2 | ConvertTo-DbaXESession -Name 'Test'

        Converts Trace with ID 2 to a Session named Test on SQL Server instances named sql2017 and sql2012 and creates the Session on each respective server.

    .EXAMPLE
        PS C:\> Get-DbaTrace -SqlInstance sql2014 | Out-GridView -PassThru | ConvertTo-DbaXESession -Name 'Test' | Start-DbaXESession

        Converts selected traces on sql2014 to sessions, creates the session, and starts it.

    .EXAMPLE
        PS C:\> Get-DbaTrace -SqlInstance sql2014 | Where-Object Id -eq 1 | ConvertTo-DbaXESession -Name 'Test' -OutputScriptOnly

        Converts trace ID 1 on sql2014 to an Extended Event and outputs the resulting T-SQL.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$InputObject,
        [parameter(Mandatory)]
        [string]$Name,
        [PSCredential]$SqlCredential,
        [switch]$OutputScriptOnly,
        [switch]$EnableException
    )
    begin {
        $rawpath = [IO.Path]::Combine($script:PSModuleRoot, "bin", "sp_SQLskills_ConvertTraceToEEs.sql")
        $rawsql = Get-Content $rawpath -Raw
    }
    process {
        foreach ($trace in $InputObject) {
            if (-not $trace.id -and -not $trace.Parent) {
                Stop-Function -Message "Input is of the wrong type. Use Get-DbaTrace." -Continue
                return
            }

            $server = $trace.Parent

            if ($server.VersionMajor -lt 11) {
                Stop-Function -Message "SQL Server version 2012+ required - $server not supported."
                return
            }

            $tempdb = $server.Databases['tempdb']
            $traceid = $trace.id

            $splatXESession = @{
                SqlInstance = $server
                Session     = $PSBoundParameters.Name
            }
            if ($SqlCredential) {
                $splatXESession["SqlCredential"] = $SqlCredential
            }

            if ((Get-DbaXESession @splatXESession)) {
                $oldname = $name
                $Name = "$name-$traceid"
                Write-Message -Level Output -Message "XE Session $oldname already exists on $server, trying $name."
            }

            $splatXESession["Session"] = $Name
            if ((Get-DbaXESession @splatXESession)) {
                $oldname = $name
                $Name = "$name-$(Get-Random)"
                Write-Message -Level Output -Message "XE Session $oldname already exists on $server, trying $name."
            }

            $sql = $rawsql.Replace("--TRACEID--", $traceid)
            $sql = $sql.Replace("--SESSIONNAME--", $name)

            try {
                Write-Message -Level Verbose -Message "Executing SQL in tempdb."
                $results = $tempdb.ExecuteWithResults($sql).Tables.Rows.SqlString
            } catch {
                Stop-Function -Message "Issue creating, dropping or executing sp_SQLskills_ConvertTraceToExtendedEvents in tempdb on $server." -Target $server -ErrorRecord $_
            }

            $results = $results -join [System.Environment]::NewLine

            if ($OutputScriptOnly) {
                $results
            } else {
                Write-Message -Level Verbose -Message "Creating XE Session $name."
                try {
                    $tempdb.ExecuteNonQuery($results)
                } catch {
                    Stop-Function -Message "Issue creating extended event $name on $server." -Target $server -ErrorRecord $_
                }
                $splatGetSession = @{
                    SqlInstance = $server
                    Session     = $name
                }
                if ($SqlCredential) {
                    $splatGetSession["SqlCredential"] = $SqlCredential
                }
                Get-DbaXESession @splatGetSession
            }
        }
    }
}
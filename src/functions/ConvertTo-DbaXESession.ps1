function ConvertTo-DbaXESession {
    <#
    .SYNOPSIS
        Uses a slightly modified version of sp_SQLskills_ConvertTraceToExtendedEvents.sql to convert Traces to Extended Events.

    .DESCRIPTION
        Uses a slightly modified version of sp_SQLskills_ConvertTraceToExtendedEvents.sql to convert Traces to Extended Events.

        T-SQL code by: Jonathan M. Kehayias, SQLskills.com. T-SQL can be found in this module directory and at
        https://www.sqlskills.com/blogs/jonathan/converting-sql-trace-to-extended-events-in-sql-server-2012/

    .PARAMETER InputObject
        Specifies a Trace object output by Get-DbaTrace.

    .PARAMETER Name
        The name of the Trace to convert. If the name exists, characters will be appended to it.

    .PARAMETER OutputScriptOnly
        Outputs the T-SQL script to create the XE session and does not execute it.

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
        [switch]$OutputScriptOnly,
        [switch]$EnableException
    )
    begin {
        $rawsql = Get-Content "$script:PSModuleRoot\bin\sp_SQLskills_ConvertTraceToEEs.sql" -Raw
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

            if ((Get-DbaXESession -SqlInstance $server -Session $PSBoundParameters.Name)) {
                $oldname = $name
                $Name = "$name-$traceid"
                Write-Message -Level Output -Message "XE Session $oldname already exists on $server, trying $name."
            }

            if ((Get-DbaXESession -SqlInstance $server -Session $Name)) {
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

            $results = $results -join "`r`n"

            if ($OutputScriptOnly) {
                $results
            } else {
                Write-Message -Level Verbose -Message "Creating XE Session $name."
                try {
                    $tempdb.ExecuteNonQuery($results)
                } catch {
                    Stop-Function -Message "Issue creating extended event $name on $server." -Target $server -ErrorRecord $_
                }
                Get-DbaXESession -SqlInstance $server -Session $name
            }
        }
    }
}
#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Invoke-DbaXeReplay {
    <#
    .SYNOPSIS
        A command to run explicit T-SQL commands or files.

    .DESCRIPTION
        This function is a wrapper command around Invoke-SqlCmd2.
        It was designed to be more convenient to use in a pipeline and to behave in a way consistent with the rest of our functions.

    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server Instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER Database
        The database(s) to execute the queries against. If left blank, the original database name will be used.

    .PARAMETER Event
        Each Response can be limited to processing specific events, while ignoring all the other ones. When this attribute is omitted, all events are processed.

    .PARAMETER InputObject
        The results of Read-DbaXESession or Watch-DbaXESession

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        Read-DbaXEFile -Path C:\temp\sample.xel | Invoke-DbaSqlCmd -SqlInstance sql2017 -Database tempdb

        Runs all batch_text for sql_batch_completed against tempdb on sql2017

    .EXAMPLE
        Read-DbaXEFile -Path C:\temp\sample.xel | Invoke-DbaSqlCmd -SqlInstance sql2017, sql2016 -Database tempdb, db1

        Runs all batch_text for sql_batch_completed against tempdb and db1 on sql2017 and sql2016

    .EXAMPLE
        Watch-DbaXESession -SqlInstance sql2017 -Session 'Profile New App' | Invoke-DbaSqlCmd -SqlInstance sql2017, sql2016 -Database tempdb, db1

        Runs all batch_text for sql_batch_completed against tempdb and db1 on sql2017 and sql2016
    #>
    Param (
        [Parameter(Mandatory)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance[]]$SqlInstance,
        [Alias("Credential")]
        [PsCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Event = @('sql_batch_completed','rcp_completed'),
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject,
        [switch]$EnableException
    )

    process {
        if ($InputObject.name -notin $Event) {
            continue
        }

        if (Test-Bound -ParameterName Database -Not) {
            $Database = switch ($InputObject.database_id) {
                1 { "master" }
                2 { "tempdb" }
                3 { "model" }
                4 { "msdb" }
                default { "$($InputObject.database_name)".Trim() }
            }
            if (-not $Database) { $Database = "tempdb" }
        }

        $querycolumns = 'statement', 'batch_text'

        if ($InputObject.statement) {
            $query = $InputObject.statement
        }
        else {
            $query = $InputObject.batch_text
        }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level VeryVerbose -Message "Connecting to $instance." -Target $instance
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($currentdb in $Database) {
                $db = Get-DbaDatabase -SqlInstance $server -Database $Database
                try {
                    $db.Query($query)
                    [pscustomobject]@{
                        SqlInstance       = $instance
                        Database          = $currentdb
                        Query             = $query
                    }
                }
                catch {
                    $message = $_.Exception.InnerException.InnerException | Out-String
                    Stop-Function -Message "Query ($query) against $currentdb on $instance failed | $message"
                }
            }
        }
    }
}
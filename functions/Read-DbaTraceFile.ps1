function Read-DbaTraceFile {
    <#
        .SYNOPSIS
        Reads a trace file from specied SQL Server Database

        .DESCRIPTION
        Using the fn_trace_gettable function, a trace file is read and returned as a PowerShell object

        This function returns the whole of the trace file. The information is presented in the format that the trace subsystem uses.

        .PARAMETER SqlInstance
        A SQL Server instance to connect to

        .PARAMETER SqlCredential
        A credential to use to conect to the SQL instance rather than using Windows Authentication

        .PARAMETER Path
        Path to the trace file. This path is relative to the SQL Server instance.

        .PARAMETER Database
        Search for results only with specific DatabaseName. Uses IN for comparisons.

        .PARAMETER Login
        Search for results only with specific Logins. Uses IN for comparisons.

        .PARAMETER Spid
        Search for results only with specific Spids. Uses IN for comparisons.

        .PARAMETER EventClass
        Search for results only with specific EventClasses. Uses IN for comparisons.

        .PARAMETER ObjectType
        Search for results only with specific ObjectTypes. Uses IN for comparisons.

        .PARAMETER Error
        Search for results only with specific Errors. Uses IN for comparisons.

        .PARAMETER EventSequence
        Search for results only with specific EventSequences. Uses IN for comparisons.

        .PARAMETER TextData
        Search for results only with specific TextData. Uses LIKE for comparisons.

        .PARAMETER ApplicationName
        Search for results only with specific ApplicationNames. Uses LIKE for comparisons.

        .PARAMETER ObjectName
        Search for results only with specific ObjectNames. Uses LIKE for comparisons.

        .PARAMETER Where
        Custom where clause - use without the word "WHERE". Here are the available columns:

        TextData
        BinaryData
        DatabaseID
        TransactionID
        LineNumber
        NTUserName
        NTDomainName
        HostName
        ClientProcessID
        ApplicationName
        LoginName
        SPID
        Duration
        StartTime
        EndTime
        Reads
        Writes
        CPU
        Permissions
        Severity
        EventSubClass
        ObjectID
        Success
        IndexID
        IntegerData
        ServerName
        EventClass
        ObjectType
        NestLevel
        State
        Error
        Mode
        Handle
        ObjectName
        DatabaseName
        FileName
        OwnerName
        RoleName
        TargetUserName
        DBUserName
        LoginSid
        TargetLoginName
        TargetLoginSid
        ColumnPermissions
        LinkedServerName
        ProviderName
        MethodName
        RowCounts
        RequestID
        XactSequence
        EventSequence
        BigintData1
        BigintData2
        GUID
        IntegerData2
        ObjectID2
        Type
        OwnerID
        ParentName
        IsSystem
        Offset
        SourceDatabaseID
        SqlHandle
        SessionLoginName
        PlanHandle
        GroupID

        .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
        Tags: Security, Trace
        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .EXAMPLE
        Read-DbaTraceFile -SqlInstance sql2016 -Database master, tempdb -Path C:\traces\big.trc

        Reads the tracefile C:\traces\big.trc, stored on the sql2016 sql server. Filters only results that have master or tempdb as the DatabaseName.

        .EXAMPLE
        Read-DbaTraceFile -SqlInstance sql2016 -Database master, tempdb -Path C:\traces\big.trc -TextData 'EXEC SP_PROCOPTION'

        Reads the tracefile C:\traces\big.trc, stored on the sql2016 sql server.
        Filters only results that have master or tempdb as the DatabaseName and that have 'EXEC SP_PROCOPTION' somewhere in the text.

        .EXAMPLE
        Read-DbaTraceFile -SqlInstance sql2016 -Path C:\traces\big.trc -Where "LinkedServerName = 'myls' and StartTime > '5/30/2017 4:27:52 PM'"

        Reads the tracefile C:\traces\big.trc, stored on the sql2016 sql server.
        Filters only results where LinkServerName = myls and StartTime is greater than '5/30/2017 4:27:52 PM'.

#>
    [CmdletBinding()]
    Param (
        [parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Path,
        [string[]]$Database,
        [string[]]$Login,
        [int[]]$Spid,
        [string[]]$EventClass,
        [string[]]$ObjectType,
        [int[]]$Error,
        [int[]]$EventSequence,
        [string[]]$TextData,
        [string[]]$ApplicationName,
        [string[]]$ObjectName,
        [string]$Where,
        [switch][Alias('Silent')]$EnableException
    )

    process {

        if ($where) {
            $Where = "where $where"
        }
        elseif ($Database -or $Login -or $Spid) {

            $tempwhere = @()

            if ($Database) {
                $where = $database -join "','"
                $tempwhere += "databasename in ('$where')"
            }

            if ($Login) {
                $where = $Login -join "','"
                $tempwhere += "LoginName in ('$where')"
            }

            if ($Spid) {
                $where = $Spid -join ","
                $tempwhere += "Spid in ($where)"
            }

            if ($EventClass) {
                $where = $EventClass -join ","
                $tempwhere += "EventClass in ($where)"
            }

            if ($ObjectType) {
                $where = $ObjectType -join ","
                $tempwhere += "ObjectType in ($where)"
            }

            if ($Error) {
                $where = $Error -join ","
                $tempwhere += "Error in ($where)"
            }

            if ($EventSequence) {
                $where = $EventSequence -join ","
                $tempwhere += "EventSequence in ($where)"
            }

            if ($TextData) {
                $where = $TextData -join "%','%"
                $tempwhere += "TextData like ('%$where%')"
            }

            if ($ApplicationName) {
                $where = $ApplicationName -join "%','%"
                $tempwhere += "ApplicationName like ('%$where%')"
            }

            if ($ObjectName) {
                $where = $ObjectName -join "%','%"
                $tempwhere += "ObjectName like ('%$where%')"
            }

            $tempwhere = $tempwhere -join " and "
            $Where = "where $tempwhere"
        }

        foreach ($instance in $sqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                return
            }

            if (Test-Bound -Parameter Path) {
                $currentpath = $path
            }
            else {
                $currentpath = $server.ConnectionContext.ExecuteScalar("Select path from sys.traces where is_default = 1")
            }

            foreach ($file in $currentpath) {
                Write-Message -Level Verbose -Message "Parsing $file"

                $exists = Test-DbaSqlPath -SqlInstance $server -Path $file

                if (!$exists) {
                    Write-Message -Level Warning -Message "Path does not exist" -Target $file
                    Continue
                }

                $sql = "select SERVERPROPERTY('MachineName') AS ComputerName,
                ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                SERVERPROPERTY('ServerName') AS SqlInstance,
                 * FROM [fn_trace_gettable]('$file', DEFAULT) $Where"
                try {
                    $server.Query($sql)
                }
                catch {
                    Stop-Function -Message "Error returned from SQL Server: $_" -Target $server -InnerErrorRecord $_
                }
            }
        }
    }
}

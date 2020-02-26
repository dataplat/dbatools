function Read-DbaTraceFile {
    <#
    .SYNOPSIS
        Reads SQL Server trace files

    .DESCRIPTION
        Using the fn_trace_gettable function, a trace file is read and returned as a PowerShell object

        This function returns the whole of the trace file. The information is presented in the format that the trace subsystem uses.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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

    .PARAMETER ErrorId
        Search for results only with specific Errors. Filters 'Error in ($ErrorId)'  Uses IN for comparisons.

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
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Read-DbaTraceFile

    .EXAMPLE
        PS C:\> Read-DbaTraceFile -SqlInstance sql2016 -Database master, tempdb -Path C:\traces\big.trc

        Reads the tracefile C:\traces\big.trc, stored on the sql2016 sql server. Filters only results that have master or tempdb as the DatabaseName.

    .EXAMPLE
        PS C:\> Read-DbaTraceFile -SqlInstance sql2016 -Database master, tempdb -Path C:\traces\big.trc -TextData 'EXEC SP_PROCOPTION'

        Reads the tracefile C:\traces\big.trc, stored on the sql2016 sql server.
        Filters only results that have master or tempdb as the DatabaseName and that have 'EXEC SP_PROCOPTION' somewhere in the text.

    .EXAMPLE
        PS C:\> Read-DbaTraceFile -SqlInstance sql2016 -Path C:\traces\big.trc -Where "LinkedServerName = 'myls' and StartTime > '5/30/2017 4:27:52 PM'"

        Reads the tracefile C:\traces\big.trc, stored on the sql2016 sql server.
        Filters only results where LinkServerName = myls and StartTime is greater than '5/30/2017 4:27:52 PM'.

    .EXAMPLE
        PS C:\> Get-DbaTrace -SqlInstance sql2014 | Read-DbaTraceFile

        Reads every trace file on sql2014

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]]$SqlInstance,
        [parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipelineByPropertyName)]
        [string[]]$Path,
        [string[]]$Database,
        [string[]]$Login,
        [int[]]$Spid,
        [string[]]$EventClass,
        [string[]]$ObjectType,
        [int[]]$ErrorId,
        [int[]]$EventSequence,
        [string[]]$TextData,
        [string[]]$ApplicationName,
        [string[]]$ObjectName,
        [string]$Where,
        [switch]$EnableException
    )

    begin {
        if ($where) {
            $Where = "where $where"
        } elseif ($Database -or $Login -or $Spid -or $ApplicationName -or $EventClass -or $ObjectName -or $ObjectType -or $EventSequence -or $ErrorId) {

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

            if ($ErrorId) {
                $where = $ErrorId -join ","
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
    }
    process {
        foreach ($instance in $sqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (Test-Bound -Parameter Path) {
                $currentPath = $path
            } else {
                $currentPath = $server.ConnectionContext.ExecuteScalar("SELECT path FROM sys.traces WHERE is_default = 1")
            }

            foreach ($file in $currentPath) {
                Write-Message -Level Verbose -Message "Parsing $file"

                $exists = Test-DbaPath -SqlInstance $server -Path $file

                if (!$exists) {
                    Write-Message -Level Warning -Message "Path does not exist" -Target $file
                    Continue
                }

                $sql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName, ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName, SERVERPROPERTY('ServerName') AS SqlInstance, *
                FROM [fn_trace_gettable]('$file', DEFAULT)
                $Where"

                Write-Message -Message "SQL: $sql" -Level Debug
                try {
                    $server.Query($sql)
                } catch {
                    Stop-Function -Message "Error returned from SQL Server: $instance" -Target $server -InnerErrorRecord $_
                }
            }
        }
    }
}
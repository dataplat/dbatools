function Read-DbaTraceFile {
    <#
    .SYNOPSIS
        Parses SQL Server trace files and extracts events for security auditing and performance analysis

    .DESCRIPTION
        Reads SQL Server trace files (.trc) using the fn_trace_gettable function and returns events as PowerShell objects for analysis. This function is essential for DBAs who need to investigate security incidents, audit database access, troubleshoot performance issues, or extract compliance data from trace files.

        The function can read both active trace files and archived trace files, including SQL Server's default trace that automatically captures configuration changes, login failures, and other critical events. You can filter results by database, login, application, event type, or use custom WHERE clauses to pinpoint specific activities.

        Common use cases include analyzing failed login attempts for security breaches, identifying slow-running queries affecting performance, tracking schema changes for change management, and extracting audit trails for compliance reporting.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Specifies the full path to the trace file (.trc) on the SQL Server instance.
        When omitted, reads from the default system trace that automatically captures configuration changes and security events.
        Use this when analyzing specific trace files created by custom traces or archived default traces.

    .PARAMETER Database
        Filters trace events to show only those affecting specific databases by name.
        Use this to focus analysis on particular databases when investigating issues or tracking changes.
        Accepts multiple database names and supports wildcards for pattern matching.

    .PARAMETER Login
        Filters trace events to show only those performed by specific SQL Server logins.
        Essential for security investigations to track activities by suspected user accounts or service accounts.
        Accepts multiple login names for comprehensive user activity analysis.

    .PARAMETER Spid
        Filters trace events to show only those from specific Session Process IDs (SPIDs).
        Useful for tracking all activities within particular database sessions or troubleshooting specific connection issues.
        Accepts multiple SPID values to monitor several concurrent sessions.

    .PARAMETER EventClass
        Filters trace events by event class numbers to focus on specific types of database activities.
        Common values include login events (14), logout events (15), SQL statements (10-12), and security audit events (102-111).
        Use this to narrow analysis to particular event types like failed logins or DDL changes.

    .PARAMETER ObjectType
        Filters trace events by the type of database object being accessed or modified.
        Common values include tables, views, stored procedures, functions, and triggers.
        Use this when investigating changes to specific types of database objects during schema modifications.

    .PARAMETER ErrorId
        Filters trace events to show only those with specific SQL Server error numbers.
        Common values include login failures (18456), permission denied (229), and deadlock victims (1205).
        Use this to focus on particular error conditions when troubleshooting recurring issues or security events.

    .PARAMETER EventSequence
        Filters trace events by their sequence number within the trace file.
        Use this to retrieve specific events when you know their exact sequence numbers from previous analysis.
        Helpful for pinpointing events that occurred at precise moments during an incident.

    .PARAMETER TextData
        Filters trace events by searching within the SQL statements or command text using pattern matching.
        Use this to find specific queries, stored procedure calls, or SQL commands that contain particular keywords.
        Supports partial text matching, making it ideal for finding all queries containing specific table names or SQL constructs.

    .PARAMETER ApplicationName
        Filters trace events by the application name that initiated the database connection.
        Use this to isolate activities from specific applications like SQL Server Management Studio, custom applications, or services.
        Supports pattern matching to group similar application names or versions together.

    .PARAMETER ObjectName
        Filters trace events by the name of the database object being accessed or modified.
        Use this to track all operations against specific tables, views, procedures, or other database objects.
        Supports pattern matching to find objects with similar naming conventions or prefixes.

    .PARAMETER Where
        Specifies a custom SQL WHERE clause for complex filtering beyond the standard parameters.
        Use this for advanced queries combining multiple conditions, date ranges, or custom logic that other parameters cannot achieve.
        Do not include the word "WHERE" - it is added automatically. Here are the available columns:

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

    .OUTPUTS
        System.Data.DataRow

        Returns one object per trace event from the SQL Server trace file, with the following properties added by the command:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)

        All other properties come from fn_trace_gettable function, including:
        - TextData: SQL statement or command text associated with the event
        - BinaryData: Binary data captured for the event
        - DatabaseID: Numeric identifier of the database
        - DatabaseName: Name of the database affected by the event
        - LoginName: SQL Server login that performed the event
        - SPID: Session Process ID of the connection
        - StartTime: DateTime when the event started
        - EndTime: DateTime when the event ended
        - Duration: Duration of the event in milliseconds
        - Reads: Number of logical disk reads
        - Writes: Number of logical disk writes
        - CPU: CPU time consumed in milliseconds
        - EventClass: Event class number (e.g., 10 for SQL:StmtCompleted, 14 for Login)
        - EventSequence: Sequential number of the event
        - ApplicationName: Name of the client application
        - HostName: Name of the client computer
        - ObjectName: Name of the database object being accessed
        - ObjectType: Type of object being accessed
        - Error: SQL Server error number if an error occurred
        - Severity: Severity level of the error
        - Success: Whether the operation succeeded (0 or 1)
        - NestLevel: Nesting level of the stored procedure
        - LineNumber: Line number within the batch or procedure
        - TransactionID: Transaction identifier
        - NTUserName: Windows domain and user name
        - NTDomainName: Windows domain name
        - ColumnPermissions: Column-level permissions being checked
        - Permissions: Object permissions being checked
        - State: Object state
        - Mode: Lock mode (if applicable)
        - Handle: Handle reference
        - OwnerName: Name of the object owner
        - RoleName: Database role name
        - TargetUserName: Target user for impersonation operations
        - DBUserName: Database user name
        - LoginSid: SQL Server login SID
        - TargetLoginName: Target login for security operations
        - TargetLoginSid: Target login SID
        - LinkedServerName: Name of linked server being accessed
        - ProviderName: OLE DB provider name
        - MethodName: OLE DB method name
        - RowCounts: Number of rows affected
        - RequestID: Batch request ID
        - XactSequence: Transaction sequence number
        - BigintData1: First 64-bit integer data
        - BigintData2: Second 64-bit integer data
        - GUID: Globally unique identifier
        - IntegerData: Integer data value
        - IntegerData2: Second integer data value
        - ObjectID: Object ID number
        - ObjectID2: Second object ID number
        - EventSubClass: Event subclass number
        - IndexID: Index ID
        - ClientProcessID: Process ID of the client application
        - ServerName: Name of the SQL Server instance
        - Type: Type identifier
        - OwnerID: Owner object ID
        - ParentName: Parent object name
        - IsSystem: Whether the object is a system object (0 or 1)
        - Offset: Offset value for the event
        - SourceDatabaseID: Source database ID
        - SqlHandle: SQL handle reference
        - SessionLoginName: Session login name
        - PlanHandle: Query plan handle
        - GroupID: Group ID for the event

        All properties are accessible using Select-Object * or standard pipeline operations.

    .NOTES
        Tags: Trace
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
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
                FROM fn_trace_gettable('$file', DEFAULT)
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
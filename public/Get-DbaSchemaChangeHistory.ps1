function Get-DbaSchemaChangeHistory {
    <#
    .SYNOPSIS
        Retrieves DDL change history from the SQL Server default system trace

    .DESCRIPTION
        Queries the default system trace to track CREATE, DROP, and ALTER operations performed on database objects, providing a complete audit trail of schema modifications. This helps DBAs identify who made changes, when they occurred, and which objects were affected without needing to manually parse trace files or enable custom auditing. Returns detailed information including login names, timestamps, application sources, and operation types for compliance reporting and troubleshooting. Only works with SQL Server 2005 and later, as the system trace didn't exist before then.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to include when searching for schema changes. Accepts multiple database names and wildcards for pattern matching.
        Use this when you need to focus on specific databases instead of scanning all databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies databases to exclude from the schema change search. Accepts multiple database names for filtering out unwanted databases.
        Use this to skip system databases, test databases, or any databases you don't want included in the change history results.

    .PARAMETER Since
        Filters results to show only DDL changes that occurred after the specified date and time. Accepts standard PowerShell date formats.
        Use this to focus on recent changes or changes within a specific time period, especially helpful for troubleshooting recent issues or compliance reporting.

    .PARAMETER Object
        Specifies the names of specific database objects to search for in the change history. Accepts multiple object names for targeted searches.
        Use this when investigating changes to particular tables, views, stored procedures, or other database objects rather than reviewing all schema changes.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Trace, Changes, Database, Utility
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaSchemaChangeHistory

    .EXAMPLE
        PS C:\> Get-DbaSchemaChangeHistory -SqlInstance localhost

        Returns all DDL changes made in all databases on the SQL Server instance localhost since the system trace began

    .EXAMPLE
        PS C:\> Get-DbaSchemaChangeHistory -SqlInstance localhost -Since (Get-Date).AddDays(-7)

        Returns all DDL changes made in all databases on the SQL Server instance localhost in the last 7 days

    .EXAMPLE
        PS C:\> Get-DbaSchemaChangeHistory -SqlInstance localhost -Database Finance, Prod -Since (Get-Date).AddDays(-7)

        Returns all DDL changes made in the Prod and Finance databases on the SQL Server instance localhost in the last 7 days

    .EXAMPLE
        PS C:\> Get-DbaSchemaChangeHistory -SqlInstance localhost -Database Finance -Object AccountsTable -Since (Get-Date).AddDays(-7)

        Returns all DDL changes made  to the AccountsTable object in the Finance database on the SQL Server instance localhost in the last 7 days

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [DbaDateTime]$Since,
        [string[]]$Object,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $TraceFileQuery = "select path from sys.traces where is_default = 1"

            $TraceFile = $server.Query($TraceFileQuery) | Select-Object Path

            if (!$TraceFile -or !$TraceFile.Path) {
                Write-Message -Level Warning -Message "No default trace file found on $instance. Schema change tracking requires the default trace to be enabled."
                continue
            }

            $Databases = $server.Databases

            if ($Database) { $Databases = $Databases | Where-Object Name -in $database }

            if ($ExcludeDatabase) { $Databases = $Databases | Where-Object Name -notin $ExcludeDatabase }

            foreach ($db in $Databases) {
                if ($db.IsAccessible -eq $false) {
                    Write-Message -Level Verbose -Message "$($db.name) is not accessible, skipping"
                }

                $sql = "SELECT  SERVERPROPERTY('MachineName') ComputerName
                      , ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') InstanceName
                      , SERVERPROPERTY('ServerName') SqlInstance
                      , tt.DatabaseName DatabaseName
                      , tt.StartTime DateModified
                      , tt.SessionLoginName LoginName
                      , tt.NTUserName UserName
                      , tt.ApplicationName ApplicationName
                      , CASE tt.EventClass
                             WHEN '46' THEN 'Create'
                             WHEN '47' THEN 'Drop'
                             WHEN '164' THEN 'Alter'
                        END DDLOperation
                      , s.name + '.' + o.name Object
                      , o.type_desc ObjectType
                FROM    sys.objects o
                        INNER JOIN sys.schemas s ON
                            s.schema_id = o.schema_id
                        CROSS APPLY (
                    SELECT  *
                    FROM    ::fn_trace_gettable('$($TraceFile.path)',default)
                    WHERE   ObjectID = o.object_id
                ) tt
                WHERE   tt.ObjectType NOT IN ( 21587 )
                        AND tt.DatabaseID = DB_ID()
                        AND tt.EventSubClass = 0"

                if ($null -ne $since) {
                    $sql = $sql + " and tt.StartTime>'$Since' "
                }
                if ($null -ne $object) {
                    $sql = $sql + " and o.name in ('$($object -join ''',''')') "
                }

                $sql = $sql + " order by tt.StartTime asc"
                Write-Message -Level Verbose -Message "Querying Database $db on $instance"
                Write-Message -Level Debug -Message "SQL: $sql"

                $db.Query($sql) | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, DatabaseName, DateModified, LoginName, UserName, ApplicationName, DDLOperation, Object, ObjectType
            }
        }
    }
}
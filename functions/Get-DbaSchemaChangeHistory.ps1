function Get-DbaSchemaChangeHistory {
    <#
    .SYNOPSIS
        Gets DDL changes logged in the system trace.

    .DESCRIPTION
        Queries the default system trace for any DDL changes in the specified time frame
        Only works with SQL 2005 and later, as the system trace didn't exist before then

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER Since
        A date from which DDL changes should be returned. Default is to start at the beginning of the current trace file

    .PARAMETER Object
        The name of a SQL Server object you want to look for changes on

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Backup, Database
        Author: Stuart Moore (@napalmgram - http://stuart-moore.com)

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            if ($Server.Version.Major -le 8) {
                Stop-Function -Message "This command doesn't support SQL Server 2000, sorry about that"
                return
            }
            $TraceFileQuery = "select path from sys.traces where is_default = 1"

            $TraceFile = $server.Query($TraceFileQuery) | Select-Object Path

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
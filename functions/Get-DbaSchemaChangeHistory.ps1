function Get-DbaSchemaChangeHistory {
    <#
    .SYNOPSIS
    Gets DDL changes logged in the system trace.

    .DESCRIPTION
    Queries the default system trace for any DDL changes in the specified timeframe
    Only works with SQL 2005 and later, as the system trace didn't exist before then

    .PARAMETER SqlInstance
    SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
    to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
    Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Database
    The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
    The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER Since
    A date from which DDL changes should be returned. Default is to start at the beggining of the current trace file

    .PARAMETER Object
    The name of a SQL Server object you want to look for changes on

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Tags: Migration, Backup, Databases
    Author: Stuart Moore (@napalmgram - http://stuart-moore.com)

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: MIT https://opensource.org/licenses/MIT

    .LINK
    https://dbatools.io/Get-DbaSchemaChangeHistory

    .EXAMPLE
    Get-DbaSchemaChangeHistory -SqlInstance localhost

    Returns all DDL changes made in all databases on the SQL Server instance localhost since the system trace began

    .EXAMPLE
    Get-DbaSchemaChangeHistory -SqlInstance localhost -Since (Get-Date).AddDays(-7)

    Returns all DDL changes made in all databases on the SQL Server instance localhost in the last 7 days

    .EXAMPLE
    Get-DbaSchemaChangeHistory -SqlInstance localhost -Database Finance, Prod -Since (Get-Date).AddDays(-7)

    Returns all DDL changes made in the Prod and Finance databases on the SQL Server instance localhost in the last 7 days

    .EXAMPLE
    Get-DbaSchemaChangeHistory -SqlInstance localhost -Database Finance -Object AccountsTable -Since (Get-Date).AddDays(-7)

    Returns all DDL changes made  to the AccountsTable object in the Finance database on the SQL Server instance localhost in the last 7 days

    #>

    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]
        $SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [DbaDateTime]$Since,
        [string[]]$Object,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
                    Stop-Function -Message "$db on $server is inaccessible" -Continue
                }

                $sql = "select SERVERPROPERTY('MachineName') AS ComputerName,
                        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                        SERVERPROPERTY('ServerName') AS SqlInstance,
                        tt.databasename as 'DatabaseName',
                        starttime as 'DateModified',
                        Sessionloginname as 'LoginName',
                        NTusername as 'UserName',
                        applicationname as 'ApplicationName',
                        case eventclass
                            When '46' Then 'Create'
                            when '47' Then 'Drop'
                            when '164' then 'Alter'
                        end as 'DDLOperation',
                        s.name+'.'+o.name as 'Object',
                        o.type_desc as 'ObjectType'
                        from
                        sys.objects o  inner join
                        sys.schemas s on s.schema_id=o.schema_id
                        cross apply (select * from ::fn_trace_gettable('$($TraceFile.path)',default) where ObjectID=o.object_id ) tt
                        where tt.objecttype not in (21587)
                        and tt.DatabaseID=db_id()
                        and tt.EventSubClass=0"

                if ($null -ne $since) {
                    $sql = $sql + " and tt.StartTime>'$Since' "
                }
                if ($null -ne $object) {
                    $sql = $sql + " and o.name in ('$($object -join ''',''')') "
                }

                $sql = $sql + " order by tt.StartTime asc"
                Write-Message -Level Verbose -Message "Querying Database $db on $instance"
                Write-Message -Level Debug -Message "SQL: $sql"

                $db.Query($sql)  | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, DatabaseName, DateModified, LoginName, UserName, ApplicationName, DDLOperation, Object, ObjectType
            }
        }
    }
}


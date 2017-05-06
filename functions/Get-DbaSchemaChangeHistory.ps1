FUNCTION Get-DbaSchemaChangeHistory {
    <#
	.SYNOPSIS
	Gets DDL changes logged in the system trace.

	.DESCRIPTION
    Queries the default system trace for any DDL changes in the specified timeframe
    Only works with SQL 2005 and later, as the system trace didn't exist before then

	.PARAMETER SqlInstance
	SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input to allow the function
	to be executed against multiple SQL Server instances.

	.PARAMETER SqlCredential
	SqlCredential object to connect as. If not specified, current Windows login will be used.

    .PARAMETER Databases
    Return backup information for only specific databases. These are only the databases that currently exist on the server.
    
    .PARAMETER Since
    A date from which DDL changes should be returned. Default is to start at the beggining of the current trace file

    .PARAMETER Object
    The name of a SQL Server object you want to look for changes on

	.PARAMETER Silent 
	Use this switch to disable any kind of verbose messages
	
	.NOTES
	Original Author: Stuart Moore (@naplamgram - http://stuart-moore.com)
	Tags: Migration, Backup
	
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Get-DbaSchemaChangeHistory

	.EXAMPLE
	Get-DbaJobCategory -SqlInstance localhost
    
    Returns all DDL changes made in all databases on the SQL Server instance localhost since the system trace began

	.EXAMPLE
	Get-DbaJobCategory -SqlInstance localhost -Since (Get-Date).AddDays(-7)

	Returns all DDL changes made in all databases on the SQL Server instance localhost in the last 7 days

	.EXAMPLE
	Get-DbaJobCategory -SqlInstance localhost -Databases Finance, Prod -Since (Get-Date).AddDays(-7)

	Returns all DDL changes made in the Prod and Finance databases on the SQL Server instance localhost in the last 7 days
	
    .EXAMPLE
	Get-DbaJobCategory -SqlInstance localhost -Databases Finance -Object AccountsTable -Since (Get-Date).AddDays(-7)

	Returns all DDL changes made  to the AccountsTable object in the Finance database on the SQL Server instance localhost in the last 7 days

	#>
	
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer")]
        [object[]]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [DbaDateTime]$Since,
        [switch]$Silent,
        [string[]]$Object

        
    )
	
	dynamicparam {
		if ($sqlinstance) {
			return Get-ParamSqlDatabases -SqlServer $sqlinstance[0] -SqlCredential $Credential
		}
	}
    begin {
        $databases = $psboundparameters.Databases

   }
	
    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"
			
            try {
                $server = Connect-SqlServer -SqlServer $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Can't connect to $instance or access denied. Skipping." -Continue
            }
            if ($Server.Version.Major -le 8)
            {
                Write-Message -Level Warning -Message "This command doesn't support SQL Server 2000, sorry about that" -Stop
            }
            $TraceFileQuery = "select path from sys.traces where is_default = 1"
			$TraceFile = $server.ConnectionContext.ExecuteWithResults($TraceFileQuery).Tables.Rows | Select-Object Path

            if ($null -eq $databases) { $databases = $server.databases.name }
            foreach ($database in $databases)
            {
                $DDLQuery = "
                    select 
                        tt.databasename as 'DatabaseName',
                        starttime as 'StartTime',
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
                if ($null -ne $since)
                {
                    $DDLQuery = $DDLquery +" and tt.StartTime>'$Since' "
                }
                if ($null -ne $object)
                {
                    $DDLQuery = $DDLQuery + " and o.name in ('$($object -join ''',''')') "
                }
                $DDLQuery = $DDLQuery + " order by tt.StartTime asc"
                $results = $server.databases[$database].ExecuteWithResults($DDLQuery).Tables.Rows | select *
                $results | Select-Object *, @{Name="SqlInstance";Expression={$server}} | Select-DefaultView -Property  SqlInstance, DatabaseName,starttime, LoginName, UserName, ApplicationName, DDLOperation, Object, ObjectType
            }	
        }
    }
}
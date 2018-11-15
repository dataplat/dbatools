function Invoke-Sqlcmd2 {
    <#
    .SYNOPSIS
        Runs a T-SQL script.

    .DESCRIPTION
        Runs a T-SQL script. Invoke-Sqlcmd2 runs the whole script and only captures the first selected result set, such as the output of PRINT statements when -verbose parameter is specified.
        Parameterized queries are supported.

        Help details below borrowed from Invoke-Sqlcmd

    .PARAMETER ServerInstance
        Specifies the SQL Server instance(s) to execute the query against.

    .PARAMETER Database
        Specifies the name of the database to execute the query against. If specified, this database will be used in the ConnectionString when establishing the connection to SQL Server.

        If a SQLConnection is provided, the default database for that connection is overridden with this database.

    .PARAMETER Query
        Specifies one or more queries to be run. The queries can be Transact-SQL, XQuery statements, or sqlcmd commands. Multiple queries in a single batch may be separated by a semicolon.

        Do not specify the sqlcmd GO separator (or, use the ParseGo parameter). Escape any double quotation marks included in the string.

        Consider using bracketed identifiers such as [MyTable] instead of quoted identifiers such as "MyTable".

    .PARAMETER InputFile
        Specifies the full path to a file to be used as the query input to Invoke-Sqlcmd2. The file can contain Transact-SQL statements, XQuery statements, sqlcmd commands and scripting variables.

    .PARAMETER Credential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        SECURITY NOTE: If you use the -Debug switch, the connectionstring including plain text password will be sent to the debug stream.

    .PARAMETER Encrypt
        If this switch is enabled, the connection to SQL Server will be made using SSL.

        This requires that the SQL Server has been set up to accept SSL requests. For information regarding setting up SSL on SQL Server, see https://technet.microsoft.com/en-us/library/ms189067(v=sql.105).aspx

    .PARAMETER QueryTimeout
        Specifies the number of seconds before the queries time out.

    .PARAMETER ConnectionTimeout
        Specifies the number of seconds before Invoke-Sqlcmd2 times out if it cannot successfully connect to an instance of the Database Engine. The timeout value must be an integer between 0 and 65534. If 0 is specified, connection attempts do not time out.

    .PARAMETER As
        Specifies output type. Valid options for this parameter are 'DataSet', 'DataTable', 'DataRow', 'PSObject', and 'SingleValue'

        PSObject output introduces overhead but adds flexibility for working with results: http://powershell.org/wp/forums/topic/dealing-with-dbnull/

    .PARAMETER SqlParameters
        Specifies a hashtable of parameters for parameterized SQL queries.  http://blog.codinghorror.com/give-me-parameterized-sql-or-give-me-death/

        Example:

    .PARAMETER AppendServerInstance
        If this switch is enabled, the SQL Server instance will be appended to PSObject and DataRow output.

    .PARAMETER ParseGo
        If this switch is enabled, "GO" statements will be handled automatically.
        Every "GO" will effectively run in a separate query, like if you issued multiple Invoke-SqlCmd2 commands.
        "GO"s will be recognized if they are on a single line, as this covers
        the 95% of the cases "GO" parsing is needed
        Note:
        Queries will always target that database, e.g. if you have this Query:
        USE DATABASE [dbname]
        GO
        SELECT * from sys.tables
        and you call it via
        Invoke-SqlCmd2 -ServerInstance instance -Database msdb -Query ...
        you'll get back tables from msdb, not dbname.


    .PARAMETER SQLConnection
        Specifies an existing SQLConnection object to use in connecting to SQL Server. If the connection is closed, an attempt will be made to open it.

    .INPUTS
        None
        You cannot pipe objects to Invoke-Sqlcmd2

    .OUTPUTS
        As PSObject:     System.Management.Automation.PSCustomObject
        As DataRow:      System.Data.DataRow
        As DataTable:    System.Data.DataTable
        As DataSet:      System.Data.DataTableCollectionSystem.Data.DataSet
        As SingleValue:  Dependent on data type in first column.

    .EXAMPLE
        Invoke-Sqlcmd2 -ServerInstance "MyComputer\MyInstance" -Query "SELECT login_time AS 'StartTime' FROM sysprocesses WHERE spid = 1"

        Connects to a named instance of the Database Engine on a computer and runs a basic T-SQL query.

        StartTime
        -----------
        2010-08-12 21:21:03.593

    .EXAMPLE
        Invoke-Sqlcmd2 -ServerInstance "MyComputer\MyInstance" -InputFile "C:\MyFolder\tsqlscript.sql" | Out-File -filePath "C:\MyFolder\tsqlscript.rpt"

        Reads a file containing T-SQL statements, runs the file, and writes the output to another file.

    .EXAMPLE
        Invoke-Sqlcmd2  -ServerInstance "MyComputer\MyInstance" -Query "PRINT 'hello world'" -Verbose

        Uses the PowerShell -Verbose parameter to return the message output of the PRINT command.
        VERBOSE: hello world

    .EXAMPLE
        Invoke-Sqlcmd2 -ServerInstance MyServer\MyInstance -Query "SELECT ServerName, VCNumCPU FROM tblServerInfo" -as PSObject | ?{$_.VCNumCPU -gt 8}
        Invoke-Sqlcmd2 -ServerInstance MyServer\MyInstance -Query "SELECT ServerName, VCNumCPU FROM tblServerInfo" -as PSObject | ?{$_.VCNumCPU}

        This example uses the PSObject output type to allow more flexibility when working with results.

        If we used DataRow rather than PSObject, we would see the following behavior:
        Each row where VCNumCPU does not exist would produce an error in the first example
        Results would include rows where VCNumCPU has DBNull value in the second example

    .EXAMPLE
        'Instance1', 'Server1/Instance1', 'Server2' | Invoke-Sqlcmd2 -query "Sp_databases" -as psobject -AppendServerInstance

        This example lists databases for each instance.  It includes a column for the ServerInstance in question.
        DATABASE_NAME          DATABASE_SIZE REMARKS        ServerInstance
        -------------          ------------- -------        --------------
        REDACTED                       88320                Instance1
        master                         17920                Instance1
    ...
        msdb                          618112                Server1/Instance1
        tempdb                        563200                Server1/Instance1
    ...
        OperationsManager           20480000                Server2

    .EXAMPLE
        #Construct a query using SQL parameters
        $Query = "SELECT ServerName, VCServerClass, VCServerContact FROM tblServerInfo WHERE VCServerContact LIKE @VCServerContact AND VCServerClass LIKE @VCServerClass"

        #Run the query, specifying values for SQL parameters
        Invoke-Sqlcmd2 -ServerInstance SomeServer\NamedInstance -Database ServerDB -query $query -SqlParameters @{ VCServerContact="%cookiemonster%"; VCServerClass="Prod" }

        ServerName    VCServerClass VCServerContact
        ----------    ------------- ---------------
        SomeServer1   Prod          cookiemonster, blah
        SomeServer2   Prod          cookiemonster
        SomeServer3   Prod          blah, cookiemonster

    .EXAMPLE
        Invoke-Sqlcmd2 -SQLConnection $Conn -Query "SELECT login_time AS 'StartTime' FROM sysprocesses WHERE spid = 1"

        Uses an existing SQLConnection and runs a basic T-SQL query against it

        StartTime
        -----------
        2010-08-12 21:21:03.593

    .EXAMPLE
        Invoke-SqlCmd -SQLConnection $Conn -Query "SELECT ServerName FROM tblServerInfo WHERE ServerName LIKE @ServerName" -SqlParameters @{"ServerName = "c-is-hyperv-1"}

        Executes a parameterized query against the existing SQLConnection, with a collection of one parameter to be passed to the query when executed.

    .NOTES
        Changelog moved to CHANGELOG.md:

        https://github.com/sqlcollaborative/Invoke-SqlCmd2/blob/master/CHANGELOG.md

    .LINK
        https://github.com/sqlcollaborative/Invoke-SqlCmd2

    .LINK
        https://github.com/RamblingCookieMonster/PowerShell

    .FUNCTIONALITY
        SQL

#>

    [CmdletBinding(DefaultParameterSetName = 'Ins-Que')]
    [OutputType([System.Management.Automation.PSCustomObject], [System.Data.DataRow], [System.Data.DataTable], [System.Data.DataTableCollection], [System.Data.DataSet])]
    param (
        [Parameter(ParameterSetName = 'Ins-Que',
            Position = 0,
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false,
            HelpMessage = 'SQL Server Instance required...')]
        [Parameter(ParameterSetName = 'Ins-Fil',
            Position = 0,
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false,
            HelpMessage = 'SQL Server Instance required...')]
        [Alias('Instance', 'Instances', 'ComputerName', 'Server', 'Servers', 'SqlInstance')]
        [ValidateNotNullOrEmpty()]
        [string[]]$ServerInstance,
        [Parameter(Position = 1,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [string]$Database,
        [Parameter(ParameterSetName = 'Ins-Que',
            Position = 2,
            Mandatory,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [Parameter(ParameterSetName = 'Con-Que',
            Position = 2,
            Mandatory,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [string]$Query,
        [Parameter(ParameterSetName = 'Ins-Fil',
            Position = 2,
            Mandatory,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [Parameter(ParameterSetName = 'Con-Fil',
            Position = 2,
            Mandatory,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [ValidateScript( { Test-Path -LiteralPath $_ })]
        [string]$InputFile,
        [Parameter(ParameterSetName = 'Ins-Que',
            Position = 3,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [Parameter(ParameterSetName = 'Ins-Fil',
            Position = 3,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [Alias('SqlCredential')]
        [System.Management.Automation.PSCredential]$Credential,
        [Parameter(ParameterSetName = 'Ins-Que',
            Position = 4,
            Mandatory = $false,
            ValueFromRemainingArguments = $false)]
        [Parameter(ParameterSetName = 'Ins-Fil',
            Position = 4,
            Mandatory = $false,
            ValueFromRemainingArguments = $false)]
        [switch]$Encrypt,
        [Parameter(Position = 5,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [Int32]$QueryTimeout = 600,
        [Parameter(ParameterSetName = 'Ins-Fil',
            Position = 6,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [Parameter(ParameterSetName = 'Ins-Que',
            Position = 6,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [Int32]$ConnectionTimeout = 15,
        [Parameter(Position = 7,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [ValidateSet("DataSet", "DataTable", "DataRow", "PSObject", "SingleValue")]
        [string]$As = "DataRow",
        [Parameter(Position = 8,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [System.Collections.IDictionary]$SqlParameters,
        [Parameter(Position = 9,
            Mandatory = $false)]
        [switch]$AppendServerInstance,
        [Parameter(Position = 10,
            Mandatory = $false)]
        [switch]$ParseGO,
        [Parameter(ParameterSetName = 'Con-Que',
            Position = 11,
            Mandatory = $false,
            ValueFromPipeline = $false,
            ValueFromPipelineByPropertyName = $false,
            ValueFromRemainingArguments = $false)]
        [Parameter(ParameterSetName = 'Con-Fil',
            Position = 11,
            Mandatory = $false,
            ValueFromPipeline = $false,
            ValueFromPipelineByPropertyName = $false,
            ValueFromRemainingArguments = $false)]
        [Alias('Connection', 'Conn')]
        [ValidateNotNullOrEmpty()]
        [System.Data.SqlClient.SQLConnection]$SQLConnection
    )

    process {
        Write-Message -Level Warning -Message "This command is no longer supported. Please use Invoke-DbaQuery instead."
    }
}
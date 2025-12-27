function Invoke-DbaQuery {
    <#
    .SYNOPSIS
        Executes T-SQL queries, scripts, and stored procedures against SQL Server instances with parameterized query support

    .DESCRIPTION
        Executes T-SQL commands against one or more SQL Server instances, supporting queries from strings, files, URLs, or SQL Server Management Objects. This is the primary dbatools command for running custom SQL against your environment, whether you're extracting data for reports, deploying scripts across multiple servers, or running maintenance commands.

        The function provides secure parameterized query execution to prevent SQL injection attacks, making it safe to use with dynamic values. You can target specific databases, execute against Availability Group listeners with ReadOnly intent, and choose from multiple output formats to match your workflow needs.

        Built for pipeline operations, it accepts multiple instances from Get-DbaRegServer or database collections from Get-DbaDatabase, allowing you to efficiently execute the same query across your entire SQL Server estate. The function handles both simple ad-hoc queries and complex stored procedure calls with input/output parameters, table-valued parameters, and Always Encrypted column support.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server Instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER Database
        Specifies the target database context for query execution. The query will run against this database regardless of any USE statements in the SQL code.
        Use this when you need to ensure queries execute in a specific database, particularly when running the same query against multiple instances with different default databases.

    .PARAMETER Query
        Contains the T-SQL commands to execute against the target instances. Supports T-SQL statements, XQuery, and SQLCMD commands with GO batch separators.
        Use this for ad-hoc queries, maintenance scripts, or data extraction commands. For complex scripts or version-controlled SQL, consider using the File parameter instead.

        Escape any double quotation marks included in the string.

        Consider using bracketed identifiers such as [MyTable] instead of quoted identifiers such as "MyTable".

    .PARAMETER QueryTimeout
        Sets the command timeout in seconds before the query is cancelled. Defaults to the connection's default timeout if not specified.
        Increase this value for long-running maintenance operations, large data exports, or complex analytical queries that need more processing time.

    .PARAMETER File
        Specifies file paths, URLs, or directories containing SQL scripts to execute. Supports individual .sql files, entire directories, or HTTP/HTTPS URLs for remote scripts.
        Use this for deploying version-controlled SQL scripts, running standardized maintenance routines, or executing scripts downloaded from repositories.

    .PARAMETER SqlObject
        Accepts SQL Server Management Objects (SMO) that will be scripted out and executed on target instances. Works with tables, views, stored procedures, functions, and other database objects.
        Use this to deploy database schema changes by passing SMO objects from a source environment to recreate them elsewhere.

    .PARAMETER As
        Controls the format of returned query results. Choose 'DataRow' (default) for typical result sets, 'PSObject' for PowerShell-friendly objects, or 'SingleValue' for scalar results.
        Use 'PSObject' when you need to pipe results to other PowerShell commands that expect objects. Use 'SingleValue' for queries returning a single value like COUNT(*) or configuration checks.

        PSObject and PSObjectArray output introduces overhead but adds flexibility for working with results: https://forums.powershell.org/t/dealing-with-dbnull/2328/2

    .PARAMETER SqlParameter
        Provides parameters for safe execution of queries with dynamic values, preventing SQL injection attacks. Accepts hashtables or SqlParameter objects from New-DbaSqlParameter.
        Use this whenever your queries include user input, dynamic values, or when calling stored procedures with input/output parameters. Essential for secure production scripts.  http://blog.codinghorror.com/give-me-parameterized-sql-or-give-me-death/

    .PARAMETER AppendServerInstance
        Adds the source SQL Server instance name as a column to query results. Particularly useful when running the same query against multiple instances.
        Use this when you need to identify which instance produced each row of results, essential for multi-instance reporting and troubleshooting scenarios.

    .PARAMETER MessagesToOutput
        Captures and returns T-SQL PRINT statements, RAISERROR messages, and other informational messages along with query results.
        Use this when debugging stored procedures, monitoring script progress, or when you need to see messages that SQL scripts output during execution.

    .PARAMETER InputObject
        Accepts database objects from the pipeline, typically from Get-DbaDatabase. The query will execute against each database in the collection.
        Use this to run the same query across multiple databases efficiently, such as checking configuration settings or gathering statistics from all user databases.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER ReadOnly
        Sets the connection to use ReadOnly application intent, directing queries to readable secondary replicas in Availability Groups.
        Use this when querying Availability Group listeners to reduce load on primary replicas and take advantage of readable secondaries for reporting workloads.

    .PARAMETER CommandType
        Defines how the Query parameter should be interpreted. Use 'Text' (default) for T-SQL statements, 'StoredProcedure' for procedure calls, or 'TableDirect' for direct table access.
        Set this to 'StoredProcedure' when calling stored procedures, which enables proper parameter handling and allows the use of output parameters.
        Further information: https://docs.microsoft.com/en-us/dotnet/api/system.data.sqlclient.sqlcommand.commandtype

    .PARAMETER NoExec
        Enables syntax and semantic validation without executing the actual statements. The SQL engine parses and compiles queries but doesn't run them.
        Use this to validate T-SQL syntax, check object references, and verify permissions before running potentially destructive scripts in production environments.

    .PARAMETER QuotedIdentifier
        Prepends SET QUOTED_IDENTIFIER ON to each batch before execution. This is required for INSERT, UPDATE, and DELETE operations on tables with filtered indexes, indexed views, computed columns, or XML indexes.
        Use this when modifying tables with filtered indexes and experiencing silent failures, as SMO connections may have QUOTED_IDENTIFIER set to OFF depending on server/database configuration.

    .PARAMETER AppendConnectionString
        Adds custom connection string parameters for specialized connection requirements like MultiSubnetFailover, encryption settings, or timeout values.
        Use this for Availability Group connections, Always Encrypted scenarios, or when you need connection properties not available through standard parameters. Authentication must still be handled via SqlInstance and SqlCredential.

    .NOTES
        Tags: Database, Query, Utility
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaQuery

    .EXAMPLE
        PS C:\> Invoke-DbaQuery -SqlInstance server\instance -Query 'SELECT foo FROM bar'

        Runs the sql query 'SELECT foo FROM bar' against the instance 'server\instance'

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance [SERVERNAME] -Group [GROUPNAME] | Invoke-DbaQuery -Query 'SELECT foo FROM bar'

        Runs the sql query 'SELECT foo FROM bar' against all instances in the group [GROUPNAME] on the CMS [SERVERNAME]

    .EXAMPLE
        PS C:\> "server1", "server1\nordwind", "server2" | Invoke-DbaQuery -File "C:\scripts\sql\rebuild.sql"

        Runs the sql commands stored in rebuild.sql against the instances "server1", "server1\nordwind" and "server2"

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance "server1", "server1\nordwind", "server2" | Invoke-DbaQuery -File "C:\scripts\sql\rebuild.sql"

        Runs the sql commands stored in rebuild.sql against all accessible databases of the instances "server1", "server1\nordwind" and "server2"

    .EXAMPLE
        PS C:\> Invoke-DbaQuery -SqlInstance . -Query 'SELECT * FROM users WHERE Givenname = @name' -SqlParameter @{ Name = "Maria" }

        Executes a simple query against the users table using SQL Parameters.
        This avoids accidental SQL Injection and is the safest way to execute queries with dynamic content.
        Keep in mind the limitations inherent in parameters - it is quite impossible to use them for content references.
        While it is possible to parameterize a where condition, it is impossible to use this to select which columns to select.
        The inserted text will always be treated as string content, and not as a reference to any SQL entity (such as columns, tables or databases).
    .EXAMPLE
        PS C:\> Invoke-DbaQuery -SqlInstance aglistener1 -ReadOnly -Query "select something from readonlydb.dbo.atable"

        Executes a query with ReadOnly application intent on aglistener1.

    .EXAMPLE
        PS C:\> Invoke-DbaQuery -SqlInstance server1 -Database tempdb -Query Example_SP -SqlParameter @{ Name = "Maria" } -CommandType StoredProcedure

        Executes a stored procedure Example_SP using SQL Parameters

    .EXAMPLE
        PS C:\> $queryParameters = @{
        >>     StartDate = $startdate
        >>     EndDate   = $enddate
        >> }
        PS C:\> Invoke-DbaQuery -SqlInstance server1 -Database tempdb -Query Example_SP -SqlParameter $queryParameters -CommandType StoredProcedure

        Executes a stored procedure Example_SP using multiple SQL Parameters

    .EXAMPLE
        PS C:\> $inparam = @()
        PS C:\> $inparam += [PSCustomObject]@{
        >>     somestring = 'string1'
        >>     somedate = '2021-07-15T01:02:00'
        >> }
        PS C:\> $inparam += [PSCustomObject]@{
        >>     somestring = 'string2'
        >>     somedate = '2021-07-15T02:03:00'
        >> }
        >> $inparamAsDataTable = ConvertTo-DbaDataTable -InputObject $inparam
        PS C:\> $inparamAsSQLParameter = New-DbaSqlParameter -SqlDbType structured -Value $inparamAsDataTable -TypeName 'dbatools_tabletype'
        PS C:\> Invoke-DbaQuery -SqlInstance localhost -Database master -CommandType StoredProcedure -Query my_proc -SqlParameter $inparamAsSQLParameter

        Creates an TVP input parameter and uses it to invoke a stored procedure.

    .EXAMPLE
        PS C:\> $output = New-DbaSqlParameter -ParameterName json_result -SqlDbType NVarChar -Size -1 -Direction Output
        PS C:\> Invoke-DbaQuery -SqlInstance localhost -Database master -CommandType StoredProcedure -Query my_proc -SqlParameter $output
        PS C:\> $output.Value

        Creates an output parameter and uses it to invoke a stored procedure.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance localhost -Database master -AlwaysEncrypted
        PS C:\> $inputparamSSN = New-DbaSqlParameter -Direction Input -ParameterName "@SSN" -DbType AnsiStringFixedLength -Size 11 -SqlValue "444-44-4444" -ForceColumnEncryption
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query 'SELECT * FROM bar WHERE SSN_col = @SSN' -SqlParameter @inputparamSSN

        Creates an input parameter using Always Encrypted

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance AG1 -Database dbatools -MultiSubnetFailover -ConnectTimeout 60
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query 'SELECT foo FROM bar'

        Reuses Connect-DbaInstance, leveraging advanced paramenters, to adhere to official guidelines to target FCI or AG listeners.
        See https://learn.microsoft.com/en-us/dotnet/framework/data/adonet/sql/sqlclient-support-for-high-availability-disaster-recovery#connecting-with-multisubnetfailover

    .EXAMPLE
        PS C:\> Invoke-DbaQuery -SqlInstance AG1 -Query 'SELECT foo FROM bar' -AppendConnectionString 'MultiSubnetFailover=true;Connect Timeout=60'

        Leverages your own parameters, giving you full power, mimicking Connect-DbaInstance's `-MultiSubnetFailover -ConnectTimeout 60`, to adhere to official guidelines to target FCI or AG listeners.
        See https://learn.microsoft.com/en-us/dotnet/framework/data/adonet/sql/sqlclient-support-for-high-availability-disaster-recovery#connecting-with-multisubnetfailover

    .EXAMPLE
        PS C:\> Invoke-DbaQuery -SqlInstance server1 -Database tempdb -Query "INSERT INTO dbo.TableWithFilteredIndex (Id, Name) VALUES (1, 'Test')" -QuotedIdentifier

        Executes an INSERT statement with QUOTED_IDENTIFIER set to ON. This is required when modifying tables that have filtered indexes, as SQL Server requires this setting for such operations.
    #>
    [CmdletBinding(DefaultParameterSetName = "Query")]
    param (
        [Parameter(ValueFromPipeline)]
        [Parameter(ParameterSetName = 'Query', Position = 0)]
        [Parameter(ParameterSetName = 'File', Position = 0)]
        [Parameter(ParameterSetName = 'SMO', Position = 0)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database,
        [Parameter(Mandatory, ParameterSetName = "Query")]
        [string]$Query,
        [Int32]$QueryTimeout,
        [Parameter(Mandatory, ParameterSetName = "File")]
        [Alias("InputFile")]
        [object[]]$File,
        [Parameter(Mandatory, ParameterSetName = "SMO")]
        [Microsoft.SqlServer.Management.Smo.SqlSmoObject[]]$SqlObject,
        [ValidateSet("DataSet", "DataTable", "DataRow", "PSObject", "PSObjectArray", "SingleValue")]
        [string]$As = "DataRow",
        [Alias("SqlParameters")]
        [psobject[]]$SqlParameter,
        [System.Data.CommandType]$CommandType = 'Text',
        [switch]$AppendServerInstance,
        [switch]$MessagesToOutput,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$ReadOnly,
        [switch]$NoExec,
        [switch]$QuotedIdentifier,
        [string]$AppendConnectionString,
        [switch]$EnableException
    )

    begin {
        Write-Message -Level Debug -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"

        if ($PSBoundParameters.SqlParameter) {
            $first = $SqlParameter | Select-Object -First 1
            if ($first -isnot [Microsoft.Data.SqlClient.SqlParameter] -and ($first -isnot [System.Collections.IDictionary] -or $SqlParameter -is [System.Collections.IDictionary[]])) {
                Stop-Function -Message "SqlParameter only accepts a single hashtable or Microsoft.Data.SqlClient.SqlParameter"
                return
            }
        }

        $splatInvokeDbaSqlAsync = @{
            As          = $As
            CommandType = $CommandType
        }

        if (Test-Bound -ParameterName "SqlParameter") {
            $splatInvokeDbaSqlAsync["SqlParameter"] = $SqlParameter
        }
        if (Test-Bound -ParameterName "AppendServerInstance") {
            $splatInvokeDbaSqlAsync["AppendServerInstance"] = $AppendServerInstance
        }
        if (Test-Bound -ParameterName "Query") {
            $splatInvokeDbaSqlAsync["Query"] = $Query
        }
        if (Test-Bound -ParameterName "QueryTimeout") {
            $splatInvokeDbaSqlAsync["QueryTimeout"] = $QueryTimeout
        }
        if (Test-Bound -ParameterName "MessagesToOutput") {
            $splatInvokeDbaSqlAsync["MessagesToOutput"] = $MessagesToOutput
        }
        if (Test-Bound -ParameterName "Verbose") {
            $splatInvokeDbaSqlAsync["Verbose"] = $PSBoundParameters.Verbose
        }
        if (Test-Bound -ParameterName "NoExec") {
            $splatInvokeDbaSqlAsync["NoExec"] = $NoExec
        }
        if (Test-Bound -ParameterName "QuotedIdentifier") {
            $splatInvokeDbaSqlAsync["QuotedIdentifier"] = $QuotedIdentifier
        }

        if (Test-Bound -ParameterName "File") {
            $files = @()
            $temporaryFiles = @()
            $temporaryFilesCount = 0
            $temporaryFilesPrefix = (97 .. 122 | Get-Random -Count 10 | ForEach-Object { [char]$_ }) -join ''

            foreach ($item in $File) {
                if ($null -eq $item) { continue }

                $type = $item.GetType().FullName

                switch ($type) {
                    "System.IO.DirectoryInfo" {
                        if (-not $item.Exists) {
                            Stop-Function -Message "Directory not found" -Category ObjectNotFound
                            return
                        }
                        $files += ($item.GetFiles() | Where-Object Extension -EQ ".sql").FullName

                    }
                    "System.IO.FileInfo" {
                        if (-not $item.Exists) {
                            Stop-Function -Message "Directory not found." -Category ObjectNotFound
                            return
                        }

                        $files += $item.FullName
                    }
                    "System.String" {
                        try {
                            if (Test-PSVersion -Maximum 4) {
                                $uri = [uri]$item
                            } else {
                                $uri = New-Object uri -ArgumentList $item
                            }
                            $uriScheme = $uri.Scheme
                        } catch {
                            $uriScheme = $null
                        }

                        switch -regex ($uriScheme) {
                            "http" {
                                $tempfile = "$(Get-DbatoolsPath -Name temp)\$temporaryFilesPrefix-$temporaryFilesCount.sql"
                                try {
                                    try {
                                        Invoke-TlsWebRequest -Uri $item -OutFile $tempfile -ErrorAction Stop
                                    } catch {
                                        (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                                        Invoke-TlsWebRequest -Uri $item -OutFile $tempfile -ErrorAction Stop
                                    }
                                    $files += $tempfile
                                    $temporaryFilesCount++
                                    $temporaryFiles += $tempfile
                                } catch {
                                    Stop-Function -Message "Failed to download file $item" -ErrorRecord $_
                                    return
                                }
                            }
                            default {
                                try {
                                    $paths = Resolve-Path $item | Select-Object -ExpandProperty Path | Get-Item -ErrorAction Stop
                                } catch {
                                    Stop-Function -Message "Failed to resolve path: $item" -ErrorRecord $_
                                    return
                                }

                                foreach ($path in $paths) {
                                    if (-not $path.PSIsContainer) {
                                        if (Test-PSVersion -Is 3) {
                                            if (([uri]$path.FullName).Scheme -ne 'file') {
                                                Stop-Function -Message "Could not resolve path $path as filesystem object"
                                                return
                                            }
                                        } else {
                                            if ((New-Object uri -ArgumentList $path).Scheme -ne 'file') {
                                                Stop-Function -Message "Could not resolve path $path as filesystem object"
                                                return
                                            }
                                        }
                                        $files += $path.FullName
                                    }
                                }
                            }
                        }
                    }
                    default {
                        Stop-Function -Message "Unkown input type: $type" -Category InvalidArgument
                        return
                    }
                }
            }
        }

        if (Test-Bound -ParameterName "SqlObject") {
            $files = @()
            $temporaryFiles = @()
            $temporaryFilesCount = 0
            $temporaryFilesPrefix = (97 .. 122 | Get-Random -Count 10 | ForEach-Object { [char]$_ }) -join ''

            foreach ($object in $SqlObject) {
                try { $code = Export-DbaScript -InputObject $object -Passthru -EnableException }
                catch {
                    Stop-Function -Message "Failed to generate script for object $object" -ErrorRecord $_
                    return
                }

                try {
                    $newfile = "$(Get-DbatoolsPath -Name temp)\$temporaryFilesPrefix-$temporaryFilesCount.sql"
                    Set-Content -Value $code -Path $newfile -Force -ErrorAction Stop -Encoding UTF8
                    $files += $newfile
                    $temporaryFilesCount++
                    $temporaryFiles += $newfile
                } catch {
                    Stop-Function -Message "Failed to write sql script to temp" -ErrorRecord $_
                    return
                }
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }
        if (Test-Bound -ParameterName "Database", "InputObject" -And) {
            Stop-Function -Category InvalidArgument -Message "You can't use -Database with piped databases"
            return
        }
        if (Test-Bound -ParameterName "SqlInstance", "InputObject" -And) {
            Stop-Function -Category InvalidArgument -Message "You can't use -SqlInstance with piped databases"
            return
        }
        if (Test-Bound -ParameterName "SqlInstance", "InputObject" -Not) {
            Stop-Function -Category InvalidArgument -Message "Please provide either SqlInstance or InputObject"
            return
        }


        foreach ($db in $InputObject) {
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db is not accessible. Skipping."
                continue
            }
            $server = $db.Parent
            $conncontext = $server.ConnectionContext
            if ($conncontext.DatabaseName -ne $db.Name) {
                # Save StatementTimeout because it might be reset on GetDatabaseConnection
                $savedStatementTimeout = $conncontext.StatementTimeout
                $conncontext = $conncontext.Copy().GetDatabaseConnection($db.Name)
                $conncontext.StatementTimeout = $savedStatementTimeout
            }
            try {
                if ($File -or $SqlObject) {
                    foreach ($item in $files) {
                        if ($null -eq $item) { continue }
                        $filePath = $(Resolve-Path -LiteralPath $item).ProviderPath
                        $QueryfromFile = [System.IO.File]::ReadAllText("$filePath")
                        Invoke-DbaAsync -SQLConnection $conncontext @splatInvokeDbaSqlAsync -Query $QueryfromFile
                    }
                } else { Invoke-DbaAsync -SQLConnection $conncontext @splatInvokeDbaSqlAsync }
            } catch {
                Stop-Function -Message "[$db] Failed during execution" -ErrorRecord $_ -Target $server -Continue
            }
        }
        foreach ($instance in $SqlInstance) {
            # Verbose output in Invoke-DbaQuery is special, because it's the only way to assure on all versions of Powershell to have separate outputs (results and messages) coming from the TSQL Query.
            # We suppress the verbosity of all other functions in order to be sure the output is consistent with what you get, e.g., executing the same in SSMS
            Write-Message -Level Debug -Message "SqlInstance passed in, will work on: $instance"
            try {
                # We got another nightmare to solve, but fortunately @andreasjordan is "the king"
                # So. Here we are with a passed down "Server" instance. Problem is, we got two VERY different
                # libraries built with VERY different agendas. And we want to get the best of both worlds.
                # This is SUCH a nightmare because Invoke-DbaQuery is THE ONLY function that CAN use a Connection
                # (Microsoft.Data.SqlClient.SqlConnection) which can be used to run PARAMETRIZED queries.
                # So, recap of the recap:
                #  1. Microsoft.Data.SqlClient.SqlConnection:
                #     PRO: is the only connection that can use Microsoft.Data.SqlClient.SqlCommand
                #          that can use [Microsoft.Data.SqlClient.SqlParameter]s
                #     CON: when using integrated auth, as in Integrated Security=True, cannot specify a DIFFERENT user than the current logged in one
                #  2. Microsoft.SqlServer.Management.Smo.Server
                #     PRO: can specify a DIFFERENT user than the current logged in one via ConnectAsUser, ConnectAsUserName, ConnectAsUserPassword when Integrated Security=True
                #     CON: cannot use Microsoft.Data.SqlClient.SqlCommand nor [Microsoft.Data.SqlClient.SqlParameter]s
                #
                # Till here, everything is clear: we want to reuse connection if we're sure the target is "95%" adherent to the supposed one
                # But, and that's a big but, the magic in Invoke-DbaQuery is making a Microsoft.SqlServer.Management.Smo.Server connection happen, let it "bleed" through here
                # land in Invoke-DbaAsync untouched, where it gets magically converted to a Microsoft.Data.SqlClient.SqlConnection, and we get the best of both worlds.
                # Thing is, the "magic" is rather ... not so magic. What it happens is that when the connection from Microsoft.SqlServer.Management.Smo.Server is "Open",
                # everything works fine, while if it's "Closed", Microsoft.Data.SqlClient.SqlConnection rehydrates a connection using the ConnectionString of Microsoft.SqlServer.Management.Smo.Server.
                # Microsoft.SqlServer.Management.Smo.Server is cheating though, because there's no connectionstring parameter that holds "log on as a different user", so, what happens is that
                # when Microsoft.Data.SqlClient.SqlConnection picks it up, rehydrates the connection that holds Integrated Security=True, and the information on "log on as a different user" is lost in
                # translation.
                # As anticipated, this happens ONLY when the connection is "Closed", because when it's "Open", no rehydration is needed, and everything works out of the box.
                # Now, another fancy thing: we want to use connection pooling by default, because pooling connection is more performant.
                # But, and that's the big but, when connection is pooled, it gets put in the "Closed" state which translates to "back to the pool, ready to be reused", as soon as no commands are actively used.
                # In dbatools world, that means pretty much that when we are here, it's always "Closed" UNLESS -NonPooledConnection is $true on Connect-DbaInstance, and that's why when we don't land here
                # we create a new instance with NonPooledConnection = $true ( see #8491 for details, also #7725 is still relevant)
                # If -NonPooled is passed, we instruct Microsoft.SqlServer.Management.Smo.Server we DON'T want pooling, so the connection stays "Open" (there's no pool to put it back),
                # and when it's "Open" we can leverage the fact that we already established a connection, verified the certificate, did the login handshake, etc AND when casting
                # to Microsoft.Data.SqlClient.SqlConnection it enables us to leverage [Microsoft.Data.SqlClient.SqlParameter]s !
                #
                # Again, here we are, but we cannot use the connection when an information is lost, which is that we are:
                #   - Integrated Security=True
                #   - using ConnectAsUser, ConnectAsUserName, ConnectAsUserPassword to "log on as a different user"

                $startedWithAnOpenConnection = # we want to bypass Connect-DbaInstance if
                ($instance.InputObject.GetType().Name -eq "Server") -and # we have Server SMO object and
                (-not $ReadOnly) -and # no readonly intent is requested and
                (-not $Database -or $instance.InputObject.ConnectionContext.DatabaseName -eq $Database) -and # the database is not set or the currently connected and
                (-not $AppendConnectionString) -and # we don't use AppendConnectionString and
                ($instance.InputObject.ConnectionContext.ConnectAsUserName -eq '') # we don't use a DIFFERENT operating system user than the current logged in
                if ($startedWithAnOpenConnection) {
                    Write-Message -Level Debug -Message "Current connection will be reused"
                    $server = $instance.InputObject
                } else {
                    $connDbaInstanceParams = @{
                        SqlInstance         = $instance
                        SqlCredential       = $SqlCredential
                        Database            = $Database
                        NonPooledConnection = $true           # see #8491 for details, also #7725 is still relevant
                        Verbose             = $false
                    }
                    if ($ReadOnly) {
                        $connDbaInstanceParams.ApplicationIntent = "ReadOnly"
                    }
                    if ($AppendConnectionString) {
                        $connDbaInstanceParams.AppendConnectionString = $AppendConnectionString
                        $connDbaInstanceParams.SqlInstance = "$instance" # pass down "as a string" so it's forced to open a new one
                    }
                    $server = Connect-DbaInstance @connDbaInstanceParams
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $instance -Continue
            }
            $conncontext = $server.ConnectionContext
            try {
                if ($File -or $SqlObject) {
                    foreach ($item in $files) {
                        if ($null -eq $item) { continue }
                        $filePath = $(Resolve-Path -LiteralPath $item).ProviderPath
                        $QueryfromFile = [System.IO.File]::ReadAllText("$filePath")
                        Invoke-DbaAsync -SQLConnection $conncontext @splatInvokeDbaSqlAsync -Query $QueryfromFile
                    }
                } else {
                    Invoke-DbaAsync -SQLConnection $conncontext @splatInvokeDbaSqlAsync
                }
            } catch {
                Stop-Function -Message "[$instance] Failed during execution" -ErrorRecord $_ -Target $instance -Continue
            }
            # if the given connection started out open, don't close it.
            if ($connDbaInstanceParams.NonPooledConnection -and -not $startedWithAnOpenConnection) {
                # Close non-pooled connection as this is not done automatically. If it is a reused Server SMO, connection will be opened again automatically on next request.
                $null = $server | Disconnect-DbaInstance -Verbose:$false
            }
        }
    }

    end {
        # Execute end even when interrupting, as only used for cleanup

        if ($temporaryFiles) {
            # Clean up temporary files that were downloaded
            foreach ($item in $temporaryFiles) {
                Remove-Item -Path $item -ErrorAction Ignore
            }
        }
    }
}
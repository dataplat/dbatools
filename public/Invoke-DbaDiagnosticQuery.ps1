function Invoke-DbaDiagnosticQuery {
    <#
    .SYNOPSIS
        Executes Glenn Berry's DMV diagnostic queries to assess SQL Server performance and health

    .DESCRIPTION
        Runs Glenn Berry's comprehensive collection of DMV-based diagnostic queries to analyze SQL Server performance, configuration, and health issues. These queries help identify common problems like blocking, high CPU usage, memory pressure, index fragmentation, and configuration issues that affect SQL Server performance.

        The diagnostic queries are developed and maintained by Glenn Berry and can be found at https://glennsqlperformance.com/resources/ along with extensive documentation. The most recent version of these diagnostic queries are included in the dbatools module, but you can also specify a custom path to run newer versions or specific query collections.

        This function automatically detects your SQL Server version (2005-2025, including Azure SQL Database) and runs the appropriate queries for that platform. You can run all queries, select specific ones interactively, or target only instance-level or database-specific diagnostics. Results are returned as structured PowerShell objects for easy analysis, filtering, and reporting. You can also export the queries as SQL files for manual execution or documentation purposes.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Can be either a string or SMO server

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Specifies a custom directory containing Glenn Berry diagnostic query script files. By default, uses the scripts included with dbatools.
        Use this when you want to run newer diagnostic query versions downloaded from Glenn Berry's website or custom query collections.

    .PARAMETER Database
        Specifies which databases to run database-specific diagnostic queries against. Accepts wildcard patterns and multiple database names.
        When omitted, all user databases are processed. System databases are automatically excluded unless explicitly specified.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from database-level diagnostic query execution. Accepts wildcard patterns and multiple database names.
        Useful when you want to run diagnostics on most databases but skip problematic or maintenance databases.

    .PARAMETER ExcludeQuery
        Excludes specific diagnostic queries from execution by their query names. Accepts multiple query names as an array.
        Use this to skip time-consuming queries like index fragmentation analysis or queries that might cause blocking during peak hours.

    .PARAMETER UseSelectionHelper
        Opens an interactive grid view showing all available diagnostic queries with descriptions for manual selection.
        Perfect for ad-hoc troubleshooting when you want to run only specific queries relevant to your current performance issue.

    .PARAMETER QueryName
        Runs only the specified diagnostic queries by their exact query names. Accepts multiple query names as an array.
        Use this when you know exactly which diagnostics you need, such as 'Wait Stats' or 'Top CPU Queries' for targeted performance analysis.

    .PARAMETER InstanceOnly
        Limits execution to server-level diagnostic queries only, skipping all database-specific queries.
        Ideal for quick instance health checks focusing on server configuration, wait statistics, and instance-wide performance metrics.

    .PARAMETER DatabaseSpecific
        Limits execution to database-level diagnostic queries only, skipping all instance-level queries.
        Use this when investigating database-specific issues like index fragmentation, table statistics, or database configuration problems.

    .PARAMETER ExcludeQueryTextColumn
        Removes the [Complete Query Text] column from diagnostic query results to reduce output size and improve performance.
        Useful when you only need query execution statistics without the actual SQL text, especially for queries with large stored procedures.

    .PARAMETER ExcludePlanColumn
        Removes the [Query Plan] column from diagnostic query results to significantly reduce memory usage and improve performance.
        Essential when processing large result sets or when execution plan XML data is not needed for your analysis.

    .PARAMETER NoColumnParsing
        Disables all column parsing and formatting for [Complete Query Text] and [Query Plan] columns, returning raw data.
        Use this for maximum performance when you need the fastest possible execution and don't require formatted output columns.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .PARAMETER OutputPath
        Specifies the directory path where exported diagnostic query SQL files will be saved when using -ExportQueries.
        Files are automatically organized by server name, database name, and query name for easy identification and manual execution.

    .PARAMETER ExportQueries
        Exports diagnostic queries as individual SQL files instead of executing them, organized by query type and target database.
        Useful for creating a library of diagnostic scripts for offline analysis, sharing with team members, or manual execution during maintenance windows.

    .NOTES
        Tags: Community, GlennBerry
        Author: Andre Kamman (@AndreKamman), andrekamman.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDiagnosticQuery

    .OUTPUTS
        PSCustomObject

        Returns one object per diagnostic query executed from Glenn Berry's query collection. Each object contains the query execution results along with metadata about the query and target database.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Number: The query number from Glenn Berry's diagnostic query collection
        - Name: The name or title of the diagnostic query
        - Description: Description of what the diagnostic query analyzes and why it's useful
        - DatabaseSpecific: Boolean indicating if the query is database-specific (true) or instance-level (false)
        - Database: Database name if DatabaseSpecific is true; null for instance-level queries
        - Notes: Status notes; "Empty Result for this Query" if no rows returned, "WhatIf - Bypassed Execution" when -WhatIf is used, null for successful executions
        - Result: The query result set as an array of DataRow objects containing the diagnostic data; null if no results or on WhatIf execution

        Special behaviors:
        - When -ExportQueries is used, no output objects are returned; only SQL files are written to disk
        - The Result property contains all columns from the diagnostic query output, formatted as DataRow objects
        - Database-specific queries return one object per database queried, with Database property populated
        - Instance-level queries return one object with Database set to null

    .EXAMPLE
        PS C:\>Invoke-DbaDiagnosticQuery -SqlInstance sql2016

        Run the selection made by the user on the Sql Server instance specified.

    .EXAMPLE
        PS C:\>Invoke-DbaDiagnosticQuery -SqlInstance sql2016 -UseSelectionHelper | Export-DbaDiagnosticQuery -Path C:\temp\gboutput

        Provides a grid view with all the queries to choose from and will run the selection made by the user on the SQL Server instance specified.
        Then it will export the results to Export-DbaDiagnosticQuery.

    .EXAMPLE
        PS C:\> Invoke-DbaDiagnosticQuery -SqlInstance localhost -ExportQueries -OutputPath "C:\temp\DiagnosticQueries"

        Export All Queries to Disk

    .EXAMPLE
        PS C:\> Invoke-DbaDiagnosticQuery -SqlInstance localhost -DatabaseSpecific -ExportQueries -OutputPath "C:\temp\DiagnosticQueries"

        Export Database Specific Queries for all User Dbs

    .EXAMPLE
        PS C:\> Invoke-DbaDiagnosticQuery -SqlInstance localhost -DatabaseSpecific -DatabaseName 'tempdb' -ExportQueries -OutputPath "C:\temp\DiagnosticQueries"

        Export Database Specific Queries For One Target Database

    .EXAMPLE
        PS C:\> Invoke-DbaDiagnosticQuery -SqlInstance localhost -DatabaseSpecific -DatabaseName 'tempdb' -ExportQueries -OutputPath "C:\temp\DiagnosticQueries" -QueryName 'Database-scoped Configurations'

        Export Database Specific Queries For One Target Database and One Specific Query

    .EXAMPLE
        PS C:\> Invoke-DbaDiagnosticQuery -SqlInstance localhost -UseSelectionHelper

        Choose Queries To Export

    .EXAMPLE
        PS C:\> [PSObject[]]$results = Invoke-DbaDiagnosticQuery -SqlInstance localhost -WhatIf

        Parse the appropriate diagnostic queries by connecting to server, and instead of running them, return as [PSCustomObject[]] to work with further

    .EXAMPLE
        PS C:\> $results = Invoke-DbaDiagnosticQuery -SqlInstance Sql2017 -DatabaseSpecific -QueryName 'Database-scoped Configurations' -DatabaseName TestStuff

        Run diagnostic queries targeted at specific database, and only run database level queries against this database.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject[]])]
    param (
        [parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias('DatabaseName')]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [object[]]$ExcludeQuery,
        [Alias('Credential')]
        [PSCredential]$SqlCredential,
        [System.IO.FileInfo]$Path,
        [string[]]$QueryName,
        [switch]$UseSelectionHelper,
        [switch]$InstanceOnly,
        [switch]$DatabaseSpecific,
        [Switch]$ExcludeQueryTextColumn,
        [Switch]$ExcludePlanColumn,
        [Switch]$NoColumnParsing,
        [string]$OutputPath,
        [switch]$ExportQueries,
        [switch]
        [switch]$EnableException
    )
    begin {
        $ProgressId = Get-Random

        function Invoke-DiagnosticQuerySelectionHelper {
            [CmdletBinding()]
            param (
                [parameter(Mandatory)]
                $ParsedScript
            )

            $ParsedScript | Select-Object QueryNr, QueryName, DBSpecific, Description | Out-GridView -Title "Diagnostic Query Overview" -OutputMode Multiple | Sort-Object QueryNr | Select-Object -ExpandProperty QueryName

        }

        Write-Message -Level Verbose -Message "Interpreting DMV Script Collections"

        if (!$Path) {
            $Path = Join-Path -Path "$script:PSModuleRoot" -ChildPath "bin\diagnosticquery"
        }

        $scriptversions = @()
        $scriptfiles = Get-ChildItem -Path "$Path\SQLServerDiagnosticQueries_*.sql"

        if (!$scriptfiles) {
            Write-Message -Level Warning -Message "Diagnostic scripts not found in $Path. Using the ones within the module."

            $Path = Join-Path -Path $base -ChildPath "\bin\diagnosticquery"

            $scriptfiles = Get-ChildItem "$base\bin\diagnosticquery\SQLServerDiagnosticQueries_*.sql"
            if (!$scriptfiles) {
                Stop-Function -Message "Unable to download scripts, do you have an internet connection? $_"
                return
            }
        }

        [int[]]$filesort = $null

        foreach ($file in $scriptfiles) {
            $filesort += $file.BaseName.Split("_")[2]
        }

        $currentdate = $filesort | Sort-Object -Descending | Select-Object -First 1

        foreach ($file in $scriptfiles) {
            if ($file.BaseName.Split("_")[2] -eq $currentdate) {
                $parsedscript = Invoke-DbaDiagnosticQueryScriptParser -filename $file.fullname -ExcludeQueryTextColumn:$ExcludeQueryTextColumn -ExcludePlanColumn:$ExcludePlanColumn -NoColumnParsing:$NoColumnParsing

                $newscript = [PSCustomObject]@{
                    Version = $file.Basename.Split("_")[1]
                    Script  = $parsedscript
                }
                $scriptversions += $newscript
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            $counter = 0
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Verbose -Message "Collecting diagnostic query data from server: $instance"
            if ($server.VersionMinor -eq 50) {
                $version = "2008R2"
            } else {
                $version = switch ($server.VersionMajor) {
                    9 { "2005" }
                    10 { "2008" }
                    11 { "2012" }
                    12 { "2014" }
                    13 { "2016" }
                    14 { "2017" }
                    15 { "2019" }
                    16 { "2022" }
                    17 { "2025" }  # Add SQL Server 2025 support
                }
            }

            # Handle SQL Server 2016 SP versions
            if ($version -eq "2016") {
                if ($server.VersionMinor -gt 5026) {
                    $version = "2016SP2"
                } else {
                    $version = "2016SP1"  # Default to SP1 since RTM file no longer exists
                }
            }

            if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                $version = "AzureDatabase"  # Match the filename: SQLServerDiagnosticQueries_AzureDatabase.sql
            }

            if (!$instanceOnly) {
                if (-not $Database) {
                    $databases = (Get-DbaDatabase -SqlInstance $server -ExcludeSystem -ExcludeDatabase $ExcludeDatabase).Name
                } else {
                    $databases = (Get-DbaDatabase -SqlInstance $server -ExcludeSystem -Database $Database -ExcludeDatabase $ExcludeDatabase).Name
                }
            }

            $parsedscript = $scriptversions | Where-Object -Property Version -eq $version | Select-Object -ExpandProperty Script

            if ($null -eq $first) { $first = $true }
            if ($UseSelectionHelper -and $first) {
                $QueryName = Invoke-DiagnosticQuerySelectionHelper $parsedscript
                $first = $false
                if ($QueryName.Count -eq 0) {
                    Write-Message -Level Output -Message "No query selected through SelectionHelper, halting script execution"
                    return
                }
            }

            if ($QueryName.Count -eq 0) {
                $QueryName = $parsedscript | Select-Object -ExpandProperty QueryName
            }

            if ($ExcludeQuery) {
                $QueryName = Compare-Object -ReferenceObject $QueryName -DifferenceObject $ExcludeQuery | Where-Object SideIndicator -eq "<=" | Select-Object -ExpandProperty InputObject
            }

            #since some database level queries can take longer (such as fragmentation) calculate progress with database specific queries * count of databases to run against into context
            $CountOfDatabases = ($databases).Count

            if ($QueryName.Count -ne 0) {
                #if running all queries, then calculate total to run by instance queries count + (db specific count * databases to run each against)
                $countDBSpecific = @($parsedscript | Where-Object { $_.QueryName -in $QueryName -and $_.DBSpecific -eq $true }).Count
                $countInstanceSpecific = @($parsedscript | Where-Object { $_.QueryName -in $QueryName -and $_.DBSpecific -eq $false }).Count
            } else {
                #if narrowing queries to database specific, calculate total to process based on instance queries count + (db specific count * databases to run each against)
                $countDBSpecific = @($parsedscript | Where-Object DBSpecific).Count
                $countInstanceSpecific = @($parsedscript | Where-Object DBSpecific -eq $false).Count

            }
            if (!$instanceonly -and !$DatabaseSpecific -and !$QueryName) {
                $scriptcount = $countInstanceSpecific + ($countDBSpecific * $CountOfDatabases )
            } elseif ($instanceOnly) {
                $scriptcount = $countInstanceSpecific
            } elseif ($DatabaseSpecific) {
                $scriptcount = $countDBSpecific * $CountOfDatabases
            } elseif ($QueryName.Count -ne 0) {
                $scriptcount = $countInstanceSpecific + ($countDBSpecific * $CountOfDatabases )


            }

            foreach ($scriptpart in $parsedscript) {
                # ensure results are null with each part, otherwise duplicated information may be returned
                $result = $null
                if (($QueryName.Count -ne 0) -and ($QueryName -notcontains $scriptpart.QueryName)) { continue }
                if (!$scriptpart.DBSpecific -and !$DatabaseSpecific) {
                    if ($ExportQueries) {
                        $null = New-Item -Path $OutputPath -ItemType Directory -Force
                        $FileName = Remove-InvalidFileNameChars ('{0}.sql' -f $Scriptpart.QueryName)
                        $FullName = Join-Path $OutputPath $FileName
                        Write-Message -Level Verbose -Message  "Creating file: $FullName"
                        $scriptPart.Text | Out-File -FilePath $FullName -Encoding UTF8 -force
                        continue
                    }

                    if ($PSCmdlet.ShouldProcess($instance, $scriptpart.QueryName)) {

                        if (-not $EnableException) {
                            $Counter++
                            Write-Progress -Id $ProgressId -ParentId 0 -Activity "Collecting diagnostic query data from $instance" -Status "Processing $counter of $scriptcount" -CurrentOperation $scriptpart.QueryName -PercentComplete (($counter / $scriptcount) * 100)
                        }

                        try {
                            $result = $server.Query($scriptpart.Text)
                            Write-Message -Level Verbose -Message "Processed $($scriptpart.QueryName) on $instance"
                            if (-not $result) {
                                [PSCustomObject]@{
                                    ComputerName     = $server.ComputerName
                                    InstanceName     = $server.ServiceName
                                    SqlInstance      = $server.DomainInstanceName
                                    Number           = $scriptpart.QueryNr
                                    Name             = $scriptpart.QueryName
                                    Description      = $scriptpart.Description
                                    DatabaseSpecific = $scriptpart.DBSpecific
                                    Database         = $null
                                    Notes            = "Empty Result for this Query"
                                    Result           = $null
                                }
                                Write-Message -Level Verbose -Message ("Empty result for Query {0} - {1} - {2}" -f $scriptpart.QueryNr, $scriptpart.QueryName, $scriptpart.Description)
                            }
                        } catch {
                            Write-Message -Level Verbose -Message ('Some error has occurred on Server: {0} - Script: {1}, result unavailable' -f $instance, $scriptpart.QueryName) -Target $instance -ErrorRecord $_
                        }
                        if ($result) {
                            [PSCustomObject]@{
                                ComputerName     = $server.ComputerName
                                InstanceName     = $server.ServiceName
                                SqlInstance      = $server.DomainInstanceName
                                Number           = $scriptpart.QueryNr
                                Name             = $scriptpart.QueryName
                                Description      = $scriptpart.Description
                                DatabaseSpecific = $scriptpart.DBSpecific
                                Database         = $null
                                Notes            = $null
                                #Result           = Select-DefaultView -InputObject $result -Property *
                                #Not using Select-DefaultView because excluding the fields below doesn't seem to work
                                Result           = $result | Select-Object * -ExcludeProperty 'Item', 'RowError', 'RowState', 'Table', 'ItemArray', 'HasErrors'
                            }

                        }
                    } else {
                        # if running WhatIf, then return the queries that would be run as an object, not just whatif output

                        [PSCustomObject]@{
                            ComputerName     = $server.ComputerName
                            InstanceName     = $server.ServiceName
                            SqlInstance      = $server.DomainInstanceName
                            Number           = $scriptpart.QueryNr
                            Name             = $scriptpart.QueryName
                            Description      = $scriptpart.Description
                            DatabaseSpecific = $scriptpart.DBSpecific
                            Database         = $null
                            Notes            = "WhatIf - Bypassed Execution"
                            Result           = $null
                        }
                    }

                } elseif ($scriptpart.DBSpecific -and !$instanceOnly) {

                    foreach ($currentdb in $databases) {
                        if ($ExportQueries) {
                            $null = New-Item -Path $OutputPath -ItemType Directory -Force
                            $FileName = Remove-InvalidFileNameChars ('{0}-{1}-{2}.sql' -f $server.DomainInstanceName, $currentDb, $Scriptpart.QueryName)
                            $FullName = Join-Path $OutputPath $FileName
                            Write-Message -Level Verbose -Message  "Creating file: $FullName"
                            $scriptPart.Text | Out-File -FilePath $FullName -encoding UTF8 -force
                            continue
                        }


                        if ($PSCmdlet.ShouldProcess(('{0} ({1})' -f $instance, $currentDb), $scriptpart.QueryName)) {

                            if (-not $EnableException) {
                                $Counter++
                                Write-Progress -Id $ProgressId -ParentId 0 -Activity "Collecting diagnostic query data from $($currentDb) on $instance" -Status ('Processing {0} of {1}' -f $counter, $scriptcount) -CurrentOperation $scriptpart.QueryName -PercentComplete (($Counter / $scriptcount) * 100)
                            }

                            Write-Message -Level Verbose -Message "Collecting diagnostic query data from $($currentDb) for $($scriptpart.QueryName) on $instance"
                            try {
                                # Azure SQL Database connections are already scoped to a specific database
                                # Using the 2-parameter Query() overload can fail with limited permissions
                                # For Azure SQL DB, use the 1-parameter overload even for DBSpecific queries
                                if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                                    $result = $server.Query($scriptpart.Text)
                                } else {
                                    $result = $server.Query($scriptpart.Text, $currentDb)
                                }
                                if (-not $result) {
                                    [PSCustomObject]@{
                                        ComputerName     = $server.ComputerName
                                        InstanceName     = $server.ServiceName
                                        SqlInstance      = $server.DomainInstanceName
                                        Number           = $scriptpart.QueryNr
                                        Name             = $scriptpart.QueryName
                                        Description      = $scriptpart.Description
                                        DatabaseSpecific = $scriptpart.DBSpecific
                                        Database         = $currentdb
                                        Notes            = "Empty Result for this Query"
                                        Result           = $null
                                    }
                                    Write-Message -Level Verbose -Message ("Empty result for Query {0} - {1} - {2}" -f $scriptpart.QueryNr, $scriptpart.QueryName, $scriptpart.Description) -Target $scriptpart -ErrorRecord $_
                                }
                            } catch {
                                Write-Message -Level Verbose -Message ('Some error has occurred on Server: {0} - Script: {1} - Database: {2}, result will not be saved' -f $instance, $scriptpart.QueryName, $currentDb) -Target $currentdb -ErrorRecord $_
                            }

                            if ($result) {
                                [PSCustomObject]@{
                                    ComputerName     = $server.ComputerName
                                    InstanceName     = $server.ServiceName
                                    SqlInstance      = $server.DomainInstanceName
                                    Number           = $scriptpart.QueryNr
                                    Name             = $scriptpart.QueryName
                                    Description      = $scriptpart.Description
                                    DatabaseSpecific = $scriptpart.DBSpecific
                                    Database         = $currentDb
                                    Notes            = $null
                                    #Result           = Select-DefaultView -InputObject $result -Property *
                                    #Not using Select-DefaultView because excluding the fields below doesn't seem to work
                                    Result           = $result | Select-Object * -ExcludeProperty 'Item', 'RowError', 'RowState', 'Table', 'ItemArray', 'HasErrors'
                                }
                            }
                        } else {
                            # if running WhatIf, then return the queries that would be run as an object, not just whatif output

                            [PSCustomObject]@{
                                ComputerName     = $server.ComputerName
                                InstanceName     = $server.ServiceName
                                SqlInstance      = $server.DomainInstanceName
                                Number           = $scriptpart.QueryNr
                                Name             = $scriptpart.QueryName
                                Description      = $scriptpart.Description
                                DatabaseSpecific = $scriptpart.DBSpecific
                                Database         = $null
                                Notes            = "WhatIf - Bypassed Execution"
                                Result           = $null
                            }
                        }
                    }
                }
            }
        }
    }
    end {
        Write-Progress -Id $ProgressId -Activity 'Invoke-DbaDiagnosticQuery' -Completed
    }
}
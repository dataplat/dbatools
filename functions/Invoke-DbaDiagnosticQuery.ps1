function Invoke-DbaDiagnosticQuery {
    <#
    .SYNOPSIS
        Invoke-DbaDiagnosticQuery runs the scripts provided by Glenn Berry's DMV scripts on specified servers

    .DESCRIPTION
        This is the main function of the Sql Server Diagnostic Queries related functions in dbatools.
        The diagnostic queries are developed and maintained by Glenn Berry and they can be found here along with a lot of documentation:
        https://glennsqlperformance.com/resources/

        The most recent version of the diagnostic queries are included in the dbatools module.
        But it is possible to download a newer set or a specific version to an alternative location and parse and run those scripts.
        It will run all or a selection of those scripts on one or multiple servers and return the result as a PowerShell Object

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Can be either a string or SMO server

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Alternate path for the diagnostic scripts

    .PARAMETER Database
        The database(s) to process. If unspecified, all databases will be processed

    .PARAMETER ExcludeDatabase
        The database(s) to exclude

    .PARAMETER ExcludeQuery
        The Queries to exclude

    .PARAMETER UseSelectionHelper
        Provides a grid view with all the queries to choose from and will run the selection made by the user on the Sql Server instance specified.

    .PARAMETER QueryName
        Only run specific query

    .PARAMETER InstanceOnly
        Run only instance level queries

    .PARAMETER DatabaseSpecific
        Run only database level queries

    .PARAMETER ExcludeQueryTextColumn
        Use this switch to exclude the [Complete Query Text] column from relevant queries

    .PARAMETER ExcludePlanColumn
        Use this switch to exclude the [Query Plan] column from relevant queries

    .PARAMETER NoColumnParsing
        Does not parse the [Complete Query Text] and [Query Plan] columns and disregards the ExcludeQueryTextColumn and NoColumnParsing switches

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .PARAMETER OutputPath
        Directory to parsed diagnostics queries to. This will split them based on server, database name, and query.

    .PARAMETER ExportQueries
        Use this switch to export the diagnostic queries to sql files. Instead of running the queries, the server will be evaluated to find the appropriate queries to run based on SQL Version.
        These sql files will then be created in the OutputDirectory

    .NOTES
        Tags: Community, GlennBerry
        Author: Andre Kamman (@AndreKamman), http://andrekamman.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDiagnosticQuery

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
    [OutputType([pscustomobject[]])]
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
                Stop-Function -Message "Unable to download scripts, do you have an internet connection? $_" -ErrorRecord $_
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

                $newscript = [pscustomobject]@{
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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
                }
            }

            if ($version -eq "2016" -and $server.VersionMinor -gt 5026 ) {
                $version = "2016SP2"
            }

            if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                $version = "AzureSQLDatabase"
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
                                [pscustomobject]@{
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
                            [pscustomobject]@{
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

                        [pscustomobject]@{
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
                                $result = $server.Query($scriptpart.Text, $currentDb)
                                if (-not $result) {
                                    [pscustomobject]@{
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
                                [pscustomobject]@{
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

                            [pscustomobject]@{
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
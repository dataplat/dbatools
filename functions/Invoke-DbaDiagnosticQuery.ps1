function Invoke-DbaDiagnosticQuery {
    <#
.SYNOPSIS
Invoke-DbaDiagnosticQuery runs the scripts provided by Glenn Berry's DMV scripts on specified servers

.DESCRIPTION
This is the main function of the Sql Server Diagnostic Queries related functions in dbatools.
The diagnostic queries are developed and maintained by Glenn Berry and they can be found here along with a lot of documentation:
http://www.sqlskills.com/blogs/glenn/category/dmv-queries/

The most recent version of the diagnostic queries are included in the dbatools module.
But it is possible to download a newer set or a specific version to an alternative location and parse and run those scripts.
It will run all or a selection of those scripts on one or multiple servers and return the result as a PowerShell Object

.PARAMETER SqlInstance
The target SQL Server. Can be either a string or SMO server

.PARAMETER SqlCredential
Allows alternative Windows or SQL login credentials to be used

.PARAMETER Path
Alternate path for the diagnostic scripts

.PARAMETER Database
The database(s) to process. If unspecified, all databases will be processed

.PARAMETER ExcludeDatabase
The database(s) to exclude

.PARAMETER UseSelectionHelper
Provides a gridview with all the queries to choose from and will run the selection made by the user on the Sql Server instance specified.

.PARAMETER QueryName
Only run specific query

.PARAMETER InstanceOnly
Run only instance level queries

.PARAMETER DatabaseSpecific
Run only database level queries

.PARAMETER NoQueryTextColumn
Use this switch to exclude the [Complete Query Text] column from relevant queries

.PARAMETER NoPlanColumn
Use this switch to exclude the [Query Plan] column from relevant queries

.PARAMETER NoColumnParsing
Does not parse the [Complete Query Text] and [Query Plan] columns and disregards the NoQueryTextColumn and NoColumnParsing switches

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.PARAMETER Confirm
Prompts to confirm certain actions

.PARAMETER WhatIf
Shows what would happen if the command would execute, but does not actually perform the command


.NOTES
Tags: Database, DMV
Author: André Kamman (@AndreKamman), http://clouddba.io
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: MIT https://opensource.org/licenses/MIT

.LINK
https://dbatools.io/Invoke-DbaDiagnosticQuery

.EXAMPLE
Invoke-DbaDiagnosticQuery -SqlInstance sql2016

Run the selection made by the user on the Sql Server instance specified.

.EXAMPLE
Invoke-DbaDiagnosticQuery -SqlInstance sql2016 -UseSelectionHelper | Export-DbaDiagnosticQuery -Path C:\temp\gboutput

Provides a gridview with all the queries to choose from and will run the selection made by the user on the SQL Server instance specified.

Then it will export the results to Export-DbaDiagnosticQuery.

#>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [System.IO.FileInfo]$Path,
        [string[]]$QueryName,
        [switch]$UseSelectionHelper,
        [switch]$InstanceOnly,
        [switch]$DatabaseSpecific,
        [Switch]$NoQueryTextColumn,
        [Switch]$NoPlanColumn,
        [Switch]$NoColumnParsing,
        [switch][Alias('Silent')]
        $EnableException
    )

    begin {

        function Invoke-DiagnosticQuerySelectionHelper {
            [CmdletBinding()]
            Param (
                [parameter(Mandatory = $true)]
                $ParsedScript
            )

            $ParsedScript | Select-Object QueryNr, QueryName, DBSpecific, Description | Out-GridView -Title "Diagnostic Query Overview" -OutputMode Multiple | Sort-Object QueryNr | Select-Object -ExpandProperty QueryName

        }

        Write-Message -Level Verbose -Message "Interpreting DMV Script Collections"

        $module = Get-Module -Name dbatools
        $base = $module.ModuleBase

        if (!$Path) {
            $Path = "$base\bin\diagnosticquery"
        }

        $scriptversions = @()
        $scriptfiles = Get-ChildItem "$Path\SQLServerDiagnosticQueries_*_*.sql"

        if (!$scriptfiles) {
            Write-Message -Level Warning -Message "Diagnostic scripts not found in $Path. Using the ones within the module."

            $Path = "$base\bin\diagnosticquery"

            $scriptfiles = Get-ChildItem "$base\bin\diagnosticquery\SQLServerDiagnosticQueries_*_*.sql"
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
                $parsedscript = Invoke-DbaDiagnosticQueryScriptParser -filename $file.fullname -NoQueryTextColumn:$NoQueryTextColumn -NoPlanColumn:$NoPlanColumn -NoColumnParsing:$NoColumnParsing

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
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Verbose -Message "Collecting diagnostic query data from server: $instance"

            if ($server.VersionMinor -eq 50) {
                $version = "2008R2"
            }
            else {
                $version = switch ($server.VersionMajor) {
                    9 { "2005" }
                    10 { "2008" }
                    11 { "2012" }
                    12 { "2014" }
                    13 { "2016" }
                    14 { "2017" }
                }
            }

            if (!$instanceOnly) {
                $databases = $server.Query("Select Name from sys.databases where name not in ('master', 'model', 'msdb', 'tempdb')")
            }

            $parsedscript = $scriptversions | Where-Object -Property Version -eq $version | Select-Object -ExpandProperty Script

            if ($null -eq $first) { $first = $true }
            if ($UseSelectionHelper -and $first) {
                $QueryName = Invoke-DiagnosticQuerySelectionHelper $parsedscript
                $first = $false
            }

            if (!$instanceonly -and !$DatabaseSpecific -and !$QueryName) {
                $scriptcount = $parsedscript.count
            }
            elseif ($instanceOnly) {
                $scriptcount = ($parsedscript | Where-Object DBSpecific -eq $false).count
            }
            elseif ($DatabaseSpecific) {
                $scriptcount = ($parsedscript | Where-Object DBSpecific).count
            }
            elseif ($QueryName.Count -ne 0) {
                $scriptcount = $QueryName.Count
            }

            foreach ($scriptpart in $parsedscript) {

                if (($QueryName.Count -ne 0) -and ($QueryName -notcontains $scriptpart.QueryName)) { continue }
                if (!$scriptpart.DBSpecific -and !$DatabaseSpecific) {
                    if ($PSCmdlet.ShouldProcess($instance, $scriptpart.QueryName)) {
                        $counter++
                        if (-not $EnableException) {
                            Write-Progress -Id 1 -ParentId 0 -Activity "Collecting diagnostic query data from $instance" -Status "Processing $counter of $scriptcount" -CurrentOperation $scriptpart.QueryName -PercentComplete (($counter / $scriptcount) * 100)
                        }

                        try {
                            $result = $server.Query($scriptpart.Text)
                            Write-Message -Level Output -Message "Processed $($scriptpart.QueryName) on $instance"

                            if (!$result) {
                                $result = [pscustomobject]@{
                                    ComputerName     = $server.NetName
                                    InstanceName     = $server.ServiceName
                                    SqlInstance      = $server.DomainInstanceName
                                    Number           = $scriptpart.QueryNr
                                    Name             = $scriptpart.QueryName
                                    Description      = $scriptpart.Description
                                    DatabaseSpecific = $scriptpart.DBSpecific
                                    DatabaseName     = $null
                                    Notes            = "Empty Result for this Query"
                                    Result           = $null
                                }
                                Write-Message -Level Verbose -Message ("Empty result for Query {0} - {1} - {2}" -f $scriptpart.QueryNr, $scriptpart.QueryName, $scriptpart.Description)
                            }
                        }
                        catch {
                            Write-Message -Level Verbose -Message ('Some error has occured on Server: {0} - Script: {1}, result unavailable' -f $instance, $scriptpart.QueryName) -Target $instance -ErrorRecord $_
                        }
                        if ($result) {

                            [pscustomobject]@{
                                ComputerName     = $server.NetName
                                InstanceName     = $server.ServiceName
                                SqlInstance      = $server.DomainInstanceName
                                Number           = $scriptpart.QueryNr
                                Name             = $scriptpart.QueryName
                                Description      = $scriptpart.Description
                                DatabaseSpecific = $scriptpart.DBSpecific
                                DatabaseName     = $null
                                Notes            = $null
                                Result           = $result | Select-Object * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors
                            }
                        }
                    }
                }
                elseif ($scriptpart.DBSpecific -and !$instanceOnly) {
                    foreach ($currentdb in $databases) {
                        $dbname = $currentdb.name
                        if ($PSCmdlet.ShouldProcess(('{0} ({1})' -f $instance, $currentdb.name), $scriptpart.QueryName)) {

                            if (-not $EnableException) { Write-Progress -Id 1 -ParentId 0 -Activity "Collecting diagnostic query data from $dbname on $instance" -Status ('Processing {0} of {1}' -f $counter, $scriptcount) -CurrentOperation $scriptpart.QueryName -PercentComplete (($Counter / $scriptcount) * 100) }
                            Write-Message -Level Output -Message "Collecting diagnostic query data from $dbname for $($scriptpart.QueryName) on $instance"
                            try {
                                $result = $server.Query($scriptpart.Text, $currentdb.Name)
                                if (!$result) {
                                    $result = [pscustomobject]@{
                                        ComputerName     = $server.NetName
                                        InstanceName     = $server.ServiceName
                                        SqlInstance      = $server.DomainInstanceName
                                        Number           = $scriptpart.QueryNr
                                        Name             = $scriptpart.QueryName
                                        Description      = $scriptpart.Description
                                        DatabaseSpecific = $scriptpart.DBSpecific
                                        DatabaseName     = $null
                                        Notes            = "Empty Result for this Query"
                                        Result           = $null
                                    }
                                    Write-Message -Level Verbose -Message ("Empty result for Query {0} - {1} - {2}" -f $scriptpart.QueryNr, $scriptpart.QueryName, $scriptpart.Description) -Target $scriptpart -ErrorRecord $_
                                }
                            }
                            catch {
                                Write-Message -Level Verbose -Message ('Some error has occured on Server: {0} - Script: {1} - Database: {2}, result will not be saved' -f $instance, $scriptpart.QueryName, $currentdb.Name) -Target $currentdb -ErrorRecord $_
                            }

                            [pscustomobject]@{
                                ComputerName     = $server.NetName
                                InstanceName     = $server.ServiceName
                                SqlInstance      = $server.DomainInstanceName
                                Number           = $scriptpart.QueryNr
                                Name             = $scriptpart.QueryName
                                Description      = $scriptpart.Description
                                DatabaseSpecific = $scriptpart.DBSpecific
                                DatabaseName     = $currentdb.name
                                Notes            = $null
                                Result           = $result | Select-Object * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors
                            }
                        }
                    }
                }
            }
        }
    }
}
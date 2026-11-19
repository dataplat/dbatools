#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Runs Glenn Berry's diagnostic queries. Port of public/Invoke-DbaDiagnosticQuery.ps1
/// (W1-108). The begin block (script discovery, undefined-$base fallback read, the
/// parser loop) rides one VERBATIM module hop returning a hashtable; its
/// Stop-Function+return path leaves the bag unemitted, which the C# side maps to the
/// Test-FunctionInterrupt gate. Each instance rides one VERBATIM hop (the version
/// switch, database discovery, the SelectionHelper (interactive) and the
/// $QueryName/$first STICKY mutations, ExcludeQuery Compare-Object, the scriptpart
/// loop with $PSCmdlet.ShouldProcess routed to the REAL cmdlet, Write-Progress,
/// per-part Query + empty-result Notes shape, the Select-Object -ExcludeProperty
/// DataRow projection, ExportQueries file writes, and the WhatIf bypass objects);
/// fn-scope mutations ($first, $QueryName, $databases) persist through the sentinel
/// state bag; the SelectionHelper's empty-pick `return` maps to a per-record HALT
/// flag (the fn's return exits the whole process block). Only SqlInstance is
/// positional (explicit Position 0 - the W1-094 law). Surface pinned by
/// migration/baselines/Invoke-DbaDiagnosticQuery.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDiagnosticQuery", SupportsShouldProcess = true)]
[OutputType(typeof(PSObject[]))]
public sealed class InvokeDbaDiagnosticQueryCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>The database(s) to include.</summary>
    [Parameter]
    [Alias("DatabaseName")]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Query name(s) to exclude.</summary>
    [Parameter]
    public object[]? ExcludeQuery { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    [Alias("Credential")]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Alternate diagnostic-script directory.</summary>
    [Parameter]
    public System.IO.FileInfo? Path { get; set; }

    /// <summary>Query name(s) to run.</summary>
    [Parameter]
    public string[]? QueryName { get; set; }

    /// <summary>Interactive query picker.</summary>
    [Parameter]
    public SwitchParameter UseSelectionHelper { get; set; }

    /// <summary>Instance-level queries only.</summary>
    [Parameter]
    public SwitchParameter InstanceOnly { get; set; }

    /// <summary>Database-level queries only.</summary>
    [Parameter]
    public SwitchParameter DatabaseSpecific { get; set; }

    /// <summary>Strips the query-text column.</summary>
    [Parameter]
    public SwitchParameter ExcludeQueryTextColumn { get; set; }

    /// <summary>Strips the plan column.</summary>
    [Parameter]
    public SwitchParameter ExcludePlanColumn { get; set; }

    /// <summary>Skips column parsing.</summary>
    [Parameter]
    public SwitchParameter NoColumnParsing { get; set; }

    /// <summary>Export directory for -ExportQueries.</summary>
    [Parameter]
    public string? OutputPath { get; set; }

    /// <summary>Exports the queries instead of running them.</summary>
    [Parameter]
    public SwitchParameter ExportQueries { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _beginBag;
    private bool _beginInterrupted;
    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        Collection<PSObject> results = NestedCommand.InvokeScoped(this, BeginScript,
            Path, ExcludeQueryTextColumn.ToBool(), ExcludePlanColumn.ToBool(), NoColumnParsing.ToBool(), EnableException.ToBool(), BoundVerbose(), BoundDebug());
        foreach (PSObject? item in results)
        {
            Hashtable? bag = item?.BaseObject as Hashtable;
            if (bag is not null && bag.ContainsKey("__w1108Begin"))
                _beginBag = bag;
        }
        // PS: the begin Stop-Function+return path exits the dot-sourced block; the
        // bag flags it - Test-FunctionInterrupt then returns every process block.
        if (_beginBag is null || LanguagePrimitives.IsTrue(_beginBag["Interrupted"]))
            _beginInterrupted = true;
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (_beginInterrupted || Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Hashtable connectParams = new Hashtable();
            connectParams["SqlInstance"] = instance;
            connectParams["SqlCredential"] = SqlCredential;
            NestedConnect.Outcome connection = NestedConnect.Connect(this, connectParams);
            if (!connection.Ok)
            {
                StopFunction("Failure", target: instance, errorRecord: connection.Failure, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            // PS: $server keeps Connect-DbaInstance's wrapper (the W1-105 dispatch law).
            object server = connection.RawServerValue ?? connection.Server!;

            bool halted = false;
            Collection<PSObject> results = NestedCommand.InvokeScoped(this, InstanceScript,
                server, instance, _beginBag!["ScriptVersions"], _beginBag!["ProgressId"],
                Database, ExcludeDatabase, ExcludeQuery, QueryName,
                UseSelectionHelper.ToBool(), InstanceOnly.ToBool(), DatabaseSpecific.ToBool(),
                OutputPath ?? "", ExportQueries.ToBool(), _state,
                EnableException.ToBool(), this, BoundVerbose(), BoundDebug());
            foreach (PSObject? item in results)
            {
                Hashtable? sentinel = item?.BaseObject as Hashtable;
                if (sentinel is not null && sentinel.ContainsKey("__w1108State"))
                {
                    _state = sentinel["__w1108State"] as Hashtable;
                    if (_state is not null && LanguagePrimitives.IsTrue(_state["halt"]))
                        halted = true;
                    continue;
                }
                WriteObject(item);
            }
            // PS: the SelectionHelper empty-pick `return` exits the whole process block.
            if (halted)
                return;
        }
    }

    protected override void EndProcessing()
    {
        // PS: the end block runs even after a begin early-return.
        NestedCommand.InvokeScoped(this, EndScript, _beginBag is not null ? _beginBag["ProgressId"] : null);
    }

    /// <summary>A bound -Debug carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundDebug()
    {
        object? debug;
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    /// <summary>A bound -Verbose carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundVerbose()
    {
        object? verbose;
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    // PS: the begin block VERBATIM (ProgressId, script discovery with the undefined
    // $base fallback read, the parser loop) - returned as a bag; the Stop-Function
    // early-return path leaves the bag unemitted.
    private const string BeginScript = """
param($Path, $ExcludeQueryTextColumn, $ExcludePlanColumn, $NoColumnParsing, $EnableException, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($Path, $ExcludeQueryTextColumn, $ExcludePlanColumn, $NoColumnParsing, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    $ProgressId = Get-Random
    $__begun = $false
    # the dot-sourced block shares this scope; the begin Stop-Function's `return`
    # exits IT, so the bag below always emits (the fn end block still runs)
    . {

    Write-Message -Level Verbose -Message "Interpreting DMV Script Collections"

    if (!$Path) {
        # $script:PSModuleRoot can resolve empty under the Pester harness (Invoke-ManualPester,
        # the RB-IMP-51 class), which turns the script path rootless. Fall back to the live
        # module's base path, the same defensive pattern as Import-DbaPfDataCollectorSetTemplate.
        $moduleRoot = $script:PSModuleRoot
        if (-not $moduleRoot) {
            $moduleRoot = (Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1).ModuleBase
        }
        $Path = Join-Path -Path "$moduleRoot" -ChildPath "bin\diagnosticquery"
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

    $__begun = $true
    }
    @{ __w1108Begin = $true; ProgressId = $ProgressId; ScriptVersions = $scriptversions; Interrupted = (-not $__begun) }
} $Path $ExcludeQueryTextColumn $ExcludePlanColumn $NoColumnParsing $EnableException $__boundVerbose $__boundDebug 3>&1
""";

    // PS: the per-instance body VERBATIM (version switch, database discovery, the
    // sticky $QueryName/$first mutations, the scriptpart loop with routed
    // ShouldProcess, progress, queries, projections, exports, WhatIf objects).
    private const string InstanceScript = """
param($server, $instance, $scriptversions, $ProgressId, $Database, $ExcludeDatabase, $ExcludeQuery, $QueryName, $UseSelectionHelper, $instanceOnly, $DatabaseSpecific, $OutputPath, $ExportQueries, $__state, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($server, $instance, $scriptversions, $ProgressId, $Database, $ExcludeDatabase, $ExcludeQuery, $QueryName, $UseSelectionHelper, $instanceOnly, $DatabaseSpecific, $OutputPath, $ExportQueries, $__state, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    function Invoke-DiagnosticQuerySelectionHelper {
        [CmdletBinding()]
        param (
            [parameter(Mandatory)]
            $ParsedScript
        )

        $ParsedScript | Select-Object QueryNr, QueryName, DBSpecific, Description | Out-GridView -Title "Diagnostic Query Overview" -OutputMode Multiple | Sort-Object QueryNr | Select-Object -ExpandProperty QueryName

    }

    # restore fn-scope locals mutated by earlier instances/records
    $__halt = $false
    if ($null -ne $__state) {
        $first = $__state.first
        $QueryName = $__state.QueryName
        $databases = $__state.databases
    }
    # the dot-sourced block shares this scope; the SelectionHelper empty-pick
    # `return` exits IT, so the halt sentinel below still emits
    . {

    $counter = 0

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
            $__halt = $true
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

            if ($__realCmdlet.ShouldProcess($instance, $scriptpart.QueryName)) {

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


                if ($__realCmdlet.ShouldProcess(('{0} ({1})' -f $instance, $currentDb), $scriptpart.QueryName)) {

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
    @{ __w1108State = @{ first = $first; QueryName = $QueryName; databases = $databases; halt = $__halt } }
} $server $instance $scriptversions $ProgressId $Database $ExcludeDatabase $ExcludeQuery $QueryName $UseSelectionHelper $instanceOnly $DatabaseSpecific $OutputPath $ExportQueries $__state $EnableException $__realCmdlet $__boundVerbose $__boundDebug 3>&1 2>&1
""";

    // PS: the end block VERBATIM.
    private const string EndScript = """
param($ProgressId)
Write-Progress -Id $ProgressId -Activity 'Invoke-DbaDiagnosticQuery' -Completed
""";
}

#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves table objects and metadata from databases. Port of public/Get-DbaDbTable.ps1;
/// the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A begin+process port. The begin block parses -Table into a $fqTns list (via Get-ObjectNameParts) carried
/// begin->process through a sentinel (_fqTns); the begin body is DOT-SOURCED so its early "No Valid Table"
/// Stop-Function+return guard still lets the sentinel emit; the loop-bound Continue inside foreach ($t in $Table)
/// is unaffected. CRUCIALLY (unlike Get-DbaDbStoredProcedure), the source process block OPENS with
/// if (Test-FunctionInterrupt) { return } - so the begin interrupt IS carried: after the dot-source the begin
/// hop captures the module interrupt variable (Get-Variable -Scope 0) and emits Interrupted; the C# field
/// _beginInterrupted then gates ProcessRecord (replicating line 170). The verbatim Test-FunctionInterrupt line is
/// kept in the body but is inert in the fresh process scope - the real gate is _beginInterrupted. No Test-Bound.
/// IncludeSystemDBs is declared on the surface but unused in the body (never passed to the hop). The continues are
/// loop-bound. No ShouldProcess. Edits: -FunctionName Get-DbaDbTable on the begin Write-Message + Stop-Function and
/// the process's four Write-Message. Surface pinned by migration/baselines/Get-DbaDbTable.json (positions 0-6,
/// IncludeSystemDBs switch non-positional, Table Name alias, InputObject VFP pos6, no ShouldProcess).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaDbTable")]
public sealed class GetDbaDbTableCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Include system databases (declared for surface parity; unused by the command body).</summary>
    [Parameter]
    public SwitchParameter IncludeSystemDBs { get; set; }

    /// <summary>Filter to the specified table(s) by (optionally schema/database-qualified) name.</summary>
    [Parameter(Position = 4)]
    [Alias("Name")]
    public string[]? Table { get; set; }

    /// <summary>Filter to tables in the specified schema(s).</summary>
    [Parameter(Position = 5)]
    public string[]? Schema { get; set; }

    /// <summary>Database object(s) piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Carried begin->process: the parsed fully-qualified table list from -Table, and the begin interrupt state.
    private object? _fqTns;
    private bool _beginInterrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Table, EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__tableBegin"))
            {
                if (sentinel["__tableBegin"] is Hashtable state)
                {
                    _fqTns = state["Fqtns"];
                    _beginInterrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                }
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void ProcessRecord()
    {
        // Replicates the source process block's opening if (Test-FunctionInterrupt) { return }:
        // a begin Stop-Function (no -Continue) sets the interrupt, carried here as _beginInterrupted.
        if (Interrupted || _beginInterrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, Schema, InputObject, EnableException.ToBool(),
            _fqTns, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }
    // PS: the begin block VERBATIM (DOT-SOURCED so the early no-valid-table Stop-Function+return still lets the
    // sentinel emit). Captures both the $fqTns list AND the begin interrupt (Get-Variable -Scope 0) - the process
    // block gates on the latter via if (Test-FunctionInterrupt). Edits: -FunctionName on Write-Message + Stop-Function.
    private const string BeginScript = """
param($Table, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string[]]$Table, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    . {
        if ($Table) {
            $fqTns = @()
            foreach ($t in $Table) {
                $fqTn = Get-ObjectNameParts -ObjectName $t

                if (-not $fqTn.Parsed) {
                    Write-Message -Level Warning -Message "Please check you are using proper three-part names. If your search value contains special characters you must use [ ] to wrap the name. The value $t could not be parsed as a valid name." -FunctionName Get-DbaDbTable -ModuleName "dbatools"
                    Continue
                }

                $fqTns += [PSCustomObject] @{
                    Database   = $fqTn.Database
                    Schema     = $fqTn.Schema
                    Table      = $fqTn.Name
                    InputValue = $fqTn.InputValue
                }
            }
            if (!$fqTns) {
                Stop-Function -Message "No Valid Table specified" -FunctionName Get-DbaDbTable
                return
            }
        }
    }
    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __tableBegin = @{ Fqtns = $fqTns; Interrupted = [bool]($__iv -and $__iv.Value) } }
} $Table $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM. Edits: -FunctionName Get-DbaDbTable on the four Write-Message. $fqTns arrives
    // carried from begin. The opening if (Test-FunctionInterrupt) { return } is inert here (fresh scope) - the real
    // begin-interrupt gate is the C# _beginInterrupted check above. The two continues are loop-bound.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Schema, $InputObject, $EnableException, $fqTns, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$ExcludeDatabase, [string[]]$Schema, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $fqTns, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase | Where-Object IsAccessible
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            Write-Message -Level Verbose -Message "Processing $db" -FunctionName Get-DbaDbTable -ModuleName "dbatools"

            # Let the SMO read all properties referenced in this command for all tables in the database in one query.
            # Downside: If some other properties were already read outside of this command in the used SMO, they are cleared.
            # Build property list based on SQL Server version
            # Note: FullTextIndex is a complex object (not a scalar property) and cannot be initialized via ClearAndInitialize
            $properties = [System.Collections.ArrayList]@("Schema", "Name", "RowCount", "HasClusteredIndex")

            # Azure SQL does not support IndexSpaceUsed and DataSpaceUsed via the SMO enumerator
            if ($server.DatabaseEngineType -ne "SqlAzureDatabase") {
                $null = $properties.Add("IndexSpaceUsed")
                $null = $properties.Add("DataSpaceUsed")
            }

            # IsPartitioned available in SQL Server 2005+ (VersionMajor 9+)
            if ($server.VersionMajor -ge 9) {
                $null = $properties.Add('IsPartitioned')
            }

            # ChangeTrackingEnabled introduced in SQL Server 2008 (VersionMajor 10)
            if ($server.VersionMajor -ge 10) {
                $null = $properties.Add('ChangeTrackingEnabled')
            }

            # IsFileTable introduced in SQL Server 2012 (VersionMajor 11)
            if ($server.VersionMajor -ge 11) {
                $null = $properties.Add('IsFileTable')
            }

            # IsMemoryOptimized introduced in SQL Server 2014 (VersionMajor 12)
            if ($server.VersionMajor -ge 12) {
                $null = $properties.Add('IsMemoryOptimized')
            }

            # IsNode and IsEdge introduced in SQL Server 2017 (VersionMajor 14)
            if ($server.VersionMajor -ge 14) {
                $null = $properties.Add('IsNode')
                $null = $properties.Add('IsEdge')
            }

            # Build URN filter for server-side filtering when -Table or -Schema is specified
            # and the ClearAndInitialize optimization is enabled via config.
            # This avoids loading ALL tables when only specific ones are requested
            $urnFilter = ''
            if (($fqTns -or $Schema) -and (Get-DbatoolsConfigValue -FullName "commands.get-dbadbtable.clearandinitialize")) {
                $filterConditions = [System.Collections.ArrayList]@()

                # Add schema filter conditions from -Schema parameter
                if ($Schema) {
                    $schemaConditions = [System.Collections.ArrayList]@()
                    foreach ($s in $Schema) {
                        $null = $schemaConditions.Add("@Schema='$s'")
                    }
                    if ($schemaConditions.Count -eq 1) {
                        $null = $filterConditions.Add($schemaConditions[0])
                    } elseif ($schemaConditions.Count -gt 1) {
                        $null = $filterConditions.Add("($($schemaConditions -join ' or '))")
                    }
                }

                # Add table name filter conditions from -Table parameter
                if ($fqTns) {
                    $tableConditions = [System.Collections.ArrayList]@()
                    foreach ($fqTn in $fqTns) {
                        # Skip if database is specified and doesn't match current database
                        if ($fqTn.Database -and $fqTn.Database -ne $db.Name) {
                            continue
                        }

                        # Only add the table name filter, schema is handled above via -Schema parameter
                        # or from the parsed table name if -Schema was not specified
                        $tableParts = [System.Collections.ArrayList]@()

                        # Add schema from table name only if -Schema parameter was not specified
                        if ($fqTn.Schema -and -not $Schema) {
                            $null = $tableParts.Add("@Schema='$($fqTn.Schema)'")
                        }

                        if ($fqTn.Table) {
                            $null = $tableParts.Add("@Name='$($fqTn.Table)'")
                        }

                        if ($tableParts.Count -gt 0) {
                            if ($tableParts.Count -eq 1) {
                                $null = $tableConditions.Add($tableParts[0])
                            } else {
                                $null = $tableConditions.Add("($($tableParts -join ' and '))")
                            }
                        }
                    }

                    if ($tableConditions.Count -gt 0) {
                        if ($tableConditions.Count -eq 1) {
                            $null = $filterConditions.Add($tableConditions[0])
                        } else {
                            $null = $filterConditions.Add("($($tableConditions -join ' or '))")
                        }
                    }
                }

                if ($filterConditions.Count -gt 0) {
                    # ClearAndInitialize expects XPath-style filter WITH outer brackets
                    # e.g., "[@Schema='dispo' and @Name='t_auftraege']"
                    # See: https://learn.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.smocollectionbase.clearandinitialize
                    $urnFilter = "[$($filterConditions -join ' and ')]"
                    Write-Message -Level Verbose -Message "Using URN filter: $urnFilter" -FunctionName Get-DbaDbTable -ModuleName "dbatools"
                }
            }

            if (Get-DbatoolsConfigValue -FullName "commands.get-dbadbtable.clearandinitialize") {
                try {
                    $db.Tables.ClearAndInitialize($urnFilter, [string[]]$properties)
                } catch {
                    Write-Message -Level Verbose -Message "ClearAndInitialize failed: $_" -FunctionName Get-DbaDbTable -ModuleName "dbatools"
                }
            }

            if ($fqTns) {
                $tables = @()
                foreach ($fqTn in $fqTns) {
                    # If the user specified a database in a three-part name, and it's not the
                    # database currently being processed, skip this table.
                    if ($fqTn.Database) {
                        if ($fqTn.Database -ne $db.Name) {
                            continue
                        }
                    }

                    $tbl = $db.tables | Where-Object { $_.Name -in $fqTn.Table -and $fqTn.Schema -in ($_.Schema, $null) -and $fqTn.Database -in ($_.Parent.Name, $null) }

                    if (-not $tbl) {
                        Write-Message -Level Verbose -Message "Could not find table $($fqTn.Table) in $db on $server" -FunctionName Get-DbaDbTable -ModuleName "dbatools"
                    }
                    $tables += $tbl
                }
            } else {
                $tables = $db.Tables
            }

            if ($Schema) {
                $tables = $tables | Where-Object Schema -in $Schema
            }

            foreach ($sqlTable in $tables) {
                $sqlTable | Add-Member -Force -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                $sqlTable | Add-Member -Force -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                $sqlTable | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                $sqlTable | Add-Member -Force -MemberType NoteProperty -Name Database -Value $db.Name

                # Build default properties list based on SQL Server version
                $defaultProps = [System.Collections.ArrayList]@("ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name")

                if ($server.DatabaseEngineType -ne "SqlAzureDatabase") {
                    $null = $defaultProps.Add("IndexSpaceUsed")
                    $null = $defaultProps.Add("DataSpaceUsed")
                }

                $null = $defaultProps.Add("RowCount")
                $null = $defaultProps.Add("HasClusteredIndex")

                # Add version-specific properties in version order
                if ($server.VersionMajor -ge 9) {
                    $null = $defaultProps.Add("IsPartitioned")
                }
                if ($server.VersionMajor -ge 10) {
                    $null = $defaultProps.Add("ChangeTrackingEnabled")
                }
                if ($server.VersionMajor -ge 11) {
                    $null = $defaultProps.Add("IsFileTable")
                }
                if ($server.VersionMajor -ge 12) {
                    $null = $defaultProps.Add("IsMemoryOptimized")
                }
                if ($server.VersionMajor -ge 14) {
                    $null = $defaultProps.Add("IsNode")
                    $null = $defaultProps.Add("IsEdge")
                }

                # FullTextIndex is a complex object but can be displayed in output (accessed on-demand)
                $null = $defaultProps.Add("FullTextIndex")

                Select-DefaultView -InputObject $sqlTable -Property $defaultProps
            }
        }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Schema $InputObject $EnableException $fqTns $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

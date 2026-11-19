#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves stored procedure objects and metadata from databases. Port of public/Get-DbaDbStoredProcedure.ps1;
/// the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A begin+process port with TWO ValueFromPipeline parameters (SqlInstance pos0, InputObject pos6). The begin
/// block parses -Name into a $fqtns list (via Get-ObjectNameParts) that is carried begin->process through a
/// sentinel (_fqtns): the begin body is DOT-SOURCED so its early "no valid procedure name" Stop-Function+return
/// guard still lets the $fqtns sentinel emit afterward (probe-confirmed); the loop-bound Continue inside
/// foreach ($t in $Name) is unaffected. The source process block has NO Test-FunctionInterrupt, so the port does
/// NOT gate process on the begin interrupt (matching source: after a non-EnableException begin Stop-Function, an
/// empty $fqtns yields all procedures). In process, Test-Bound SqlInstance -> $__boundSqlInstance and
/// $ExcludeSystemSpIsBound = Test-Bound -ParameterName ExcludeSystemSp -> = $__boundExcludeSystemSp (ExcludeSystemSp
/// is Test-Bound-only, an untyped carried flag - not a value-passed [switch], so no positional-binding hazard).
/// The three continue statements are loop-bound. No ShouldProcess. Edits: -FunctionName Get-DbaDbStoredProcedure
/// on the begin Write-Message + Stop-Function and the process's four Write-Message. Surface pinned by
/// migration/baselines/Get-DbaDbStoredProcedure.json (positions 0-6, ExcludeSystemSp switch non-positional, two VFP, no ShouldProcess).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaDbStoredProcedure")]
public sealed class GetDbaDbStoredProcedureCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Exclude system stored procedures from the results.</summary>
    [Parameter]
    public SwitchParameter ExcludeSystemSp { get; set; }

    /// <summary>Filter to the specified stored procedure(s) by (optionally schema/database-qualified) name.</summary>
    [Parameter(Position = 4)]
    public string[]? Name { get; set; }

    /// <summary>Filter to stored procedures in the specified schema(s).</summary>
    [Parameter(Position = 5)]
    public string[]? Schema { get; set; }

    /// <summary>Database object(s) piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Carried begin->process: the parsed fully-qualified name list from -Name.
    private object? _fqtns;

    protected override void BeginProcessing()
    {

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Name, EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__spBegin"))
            {
                if (sentinel["__spBegin"] is Hashtable state)
                {
                    _fqtns = state["Fqtns"];
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

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, Schema, InputObject, EnableException.ToBool(),
            _fqtns, TestBound(nameof(SqlInstance)), TestBound(nameof(ExcludeSystemSp)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
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
    // PS: the begin block VERBATIM (DOT-SOURCED so the early no-valid-name Stop-Function+return still lets the
    // $fqtns sentinel emit). Edits: -FunctionName Get-DbaDbStoredProcedure on the Write-Message + Stop-Function.
    private const string BeginScript = """
param($Name, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string[]]$Name, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    . {
        if ($Name) {
            $fqtns = @()
            foreach ($t in $Name) {
                $fqtn = Get-ObjectNameParts -ObjectName $t

                if (!$fqtn.Parsed) {
                    Write-Message -Level Warning -Message "Please check you are using proper two-part or three-part names. If your search value contains special characters you must use [ ] to wrap the name. The value $t could not be parsed as a valid name." -FunctionName Get-DbaDbStoredProcedure -ModuleName "dbatools"
                    Continue
                }

                $fqtns += [PSCustomObject] @{
                    Database   = $fqtn.Database
                    Schema     = $fqtn.Schema
                    Procedure  = $fqtn.Name
                    InputValue = $fqtn.InputValue
                }
            }
            if (!$fqtns) {
                Stop-Function -Message "No valid procedure name specified" -FunctionName Get-DbaDbStoredProcedure
                return
            }
        }
    }
    @{ __spBegin = @{ Fqtns = $fqtns } }
} $Name $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM. Edits: -FunctionName Get-DbaDbStoredProcedure on the four Write-Message;
    // Test-Bound SqlInstance -> $__boundSqlInstance; $ExcludeSystemSpIsBound = Test-Bound -ParameterName
    // ExcludeSystemSp -> = $__boundExcludeSystemSp. $fqtns arrives carried from begin. Continues are loop-bound.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Schema, $InputObject, $EnableException, $fqtns, $__boundSqlInstance, $__boundExcludeSystemSp, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, [string[]]$Schema, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $fqtns, $__boundSqlInstance, $__boundExcludeSystemSp, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if ($__boundSqlInstance) {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        $ExcludeSystemSpIsBound = $__boundExcludeSystemSp

        foreach ($db in $InputObject) {
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db is not accessible. Skipping." -FunctionName Get-DbaDbStoredProcedure -ModuleName "dbatools"
                continue
            }

            # Let the SMO read all properties referenced in this command for all stored procedures in the database in one query.
            # Downside: If some other properties were already read outside of this command in the used SMO, they are cleared.
            try {
                $db.StoredProcedures.ClearAndInitialize('', [string[]]('Schema', 'Name', 'ID', 'CreateDate', 'DateLastModified', 'ImplementationType', 'Startup', 'IsSystemObject'))
            } catch {
                Write-Message -Level Verbose -Message "ClearAndInitialize failed: $_" -FunctionName Get-DbaDbStoredProcedure -ModuleName "dbatools"
            }

            if ($db.StoredProcedures.Count -eq 0) {
                Write-Message -Message "No Stored Procedures exist in the $db database on $instance" -Target $db -Level Output -FunctionName Get-DbaDbStoredProcedure -ModuleName "dbatools"
                continue
            }

            if ($fqtns) {
                $procs = @()
                foreach ($fqtn in $fqtns) {
                    # If the user specified a database in a three-part name, and it's not the
                    # database currently being processed, skip this procedure.
                    if ($fqtn.Database) {
                        if ($fqtn.Database -ne $db.Name) {
                            continue
                        }
                    }

                    $p = $db.StoredProcedures | Where-Object { $_.Name -in $fqtn.Procedure -and $fqtn.Schema -in ($_.Schema, $null) -and $fqtn.Database -in ($_.Parent.Name, $null) }

                    if (-not $p) {
                        Write-Message -Level Verbose -Message "Could not find procedure $($fqtn.Name) in $db on $server" -FunctionName Get-DbaDbStoredProcedure -ModuleName "dbatools"
                    }

                    $procs += $p
                }
            } else {
                $procs = $db.StoredProcedures
            }

            if ($Schema) {
                $procs = $procs | Where-Object { $_.Schema -in $Schema }
            }

            foreach ($proc in $procs) {
                if ($ExcludeSystemSpIsBound -and $proc.IsSystemObject ) {
                    continue
                }

                Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name ComputerName -value $proc.Parent.ComputerName
                Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name InstanceName -value $proc.Parent.InstanceName
                Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name SqlInstance -value $proc.Parent.SqlInstance
                Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name Database -value $db.Name
                Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name DatabaseId -value $db.Id

                $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Schema', 'ID as ObjectId', 'CreateDate',
                'DateLastModified', 'Name', 'ImplementationType', 'Startup'
                Select-DefaultView -InputObject $proc -Property $defaults
            }
        }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Schema $InputObject $EnableException $fqtns $__boundSqlInstance $__boundExcludeSystemSp $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Reads SQL Server trace files (.trc) via fn_trace_gettable, optionally filtered by a set of column
/// predicates or a raw WHERE clause.
/// </summary>
/// <remarks>
/// The WHERE-clause assembly, the default-trace path lookup, the fn_trace_gettable query, and the result
/// projection all run the original dbatools PowerShell body VERBATIM inside the dbatools module scope
/// rather than being reimplemented in C#, so the engine decides the observable details.
///
/// The begin block builds the $Where filter string once from the column predicates (or the raw -Where),
/// carried to the process records via a sentinel. The process body runs in a PER-RECORD hop (SqlInstance
/// and Path are ValueFromPipelineByPropertyName, and the query output is emitted per record), so streaming
/// is preserved and Test-Bound is evaluated at the record it belongs to. The process locals ($server,
/// $currentPath, ...) are reassigned before use in each record's instance loop (the connect-failure
/// Stop-Function -Continue skips to the next instance), so no cross-record local carry is needed. The
/// "Continue" on a missing path is a normal loop continue of "foreach ($file in $currentPath)" (a real
/// enclosing loop), not a bare-continue-across-records.
///
/// Substitutions: -FunctionName on the direct Stop-Function/Write-Message sites, and Test-Bound -Parameter
/// Path -> the carried $__pathBound flag (Test-Bound never rides the hop). $Where is supplied from the begin
/// carry. Each fn_trace_gettable result set emits before a later file or instance may fail under
/// -EnableException, so the process hop uses InvokeScopedStreaming. Surface pinned by
/// migration/baselines/Read-DbaTraceFile.json.
/// </remarks>
[Cmdlet(VerbsCommunications.Read, "DbaTraceFile")]
public sealed class ReadDbaTraceFileCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The trace file path(s) to read; defaults to the instance's default trace.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 2)]
    public string[]? Path { get; set; }

    /// <summary>Filter to these database names.</summary>
    [Parameter(Position = 3)]
    public string[]? Database { get; set; }

    /// <summary>Filter to these login names.</summary>
    [Parameter(Position = 4)]
    public string[]? Login { get; set; }

    /// <summary>Filter to these SPIDs.</summary>
    [Parameter(Position = 5)]
    public int[]? Spid { get; set; }

    /// <summary>Filter to these event classes.</summary>
    [Parameter(Position = 6)]
    public string[]? EventClass { get; set; }

    /// <summary>Filter to these object types.</summary>
    [Parameter(Position = 7)]
    public string[]? ObjectType { get; set; }

    /// <summary>Filter to these error ids.</summary>
    [Parameter(Position = 8)]
    public int[]? ErrorId { get; set; }

    /// <summary>Filter to these event sequences.</summary>
    [Parameter(Position = 9)]
    public int[]? EventSequence { get; set; }

    /// <summary>Filter to rows whose text data matches these values.</summary>
    [Parameter(Position = 10)]
    public string[]? TextData { get; set; }

    /// <summary>Filter to these application names.</summary>
    [Parameter(Position = 11)]
    public string[]? ApplicationName { get; set; }

    /// <summary>Filter to these object names.</summary>
    [Parameter(Position = 12)]
    public string[]? ObjectName { get; set; }

    /// <summary>A raw WHERE clause (used verbatim when supplied).</summary>
    [Parameter(Position = 13)]
    public string? Where { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The WHERE clause built once in the begin hop and carried to every record.
    private object? _where;

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Database, Login, Spid, EventClass, ObjectType, ErrorId, EventSequence, TextData,
            ApplicationName, ObjectName, Where,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__readDbaTraceFileBegin"))
            {
                if (sentinel["__readDbaTraceFileBegin"] is Hashtable state)
                {
                    _where = state["Where"];
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
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Path, _where, EnableException.ToBool(), TestBound(nameof(Path)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block VERBATIM, building $Where and returning it via a sentinel. Runs once.
    private const string BeginScript = """
param($Database, $Login, $Spid, $EventClass, $ObjectType, $ErrorId, $EventSequence, $TextData, $ApplicationName, $ObjectName, $Where, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param([string[]]$Database, [string[]]$Login, [int[]]$Spid, [string[]]$EventClass, [string[]]$ObjectType, [int[]]$ErrorId, [int[]]$EventSequence, [string[]]$TextData, [string[]]$ApplicationName, [string[]]$ObjectName, [string]$Where)
    if ($where) {
        $Where = "where $where"
    } elseif ($Database -or $Login -or $Spid -or $ApplicationName -or $EventClass -or $ObjectName -or $ObjectType -or $EventSequence -or $ErrorId) {

        $tempwhere = @()

        if ($Database) {
            $where = $database -join "','"
            $tempwhere += "databasename in ('$where')"
        }

        if ($Login) {
            $where = $Login -join "','"
            $tempwhere += "LoginName in ('$where')"
        }

        if ($Spid) {
            $where = $Spid -join ","
            $tempwhere += "Spid in ($where)"
        }

        if ($EventClass) {
            $where = $EventClass -join ","
            $tempwhere += "EventClass in ($where)"
        }

        if ($ObjectType) {
            $where = $ObjectType -join ","
            $tempwhere += "ObjectType in ($where)"
        }

        if ($ErrorId) {
            $where = $ErrorId -join ","
            $tempwhere += "Error in ($where)"
        }

        if ($EventSequence) {
            $where = $EventSequence -join ","
            $tempwhere += "EventSequence in ($where)"
        }

        if ($TextData) {
            $where = $TextData -join "%','%"
            $tempwhere += "TextData like ('%$where%')"
        }

        if ($ApplicationName) {
            $where = $ApplicationName -join "%','%"
            $tempwhere += "ApplicationName like ('%$where%')"
        }

        if ($ObjectName) {
            $where = $ObjectName -join "%','%"
            $tempwhere += "ObjectName like ('%$where%')"
        }

        $tempwhere = $tempwhere -join " and "
        $Where = "where $tempwhere"
    }
    @{ __readDbaTraceFileBegin = @{ Where = $Where } }
} $Database $Login $Spid $EventClass $ObjectType $ErrorId $EventSequence $TextData $ApplicationName $ObjectName $Where @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM apart from -FunctionName Read-DbaTraceFile on the direct
    // Stop-Function/Write-Message sites, Test-Bound -Parameter Path -> the carried $__pathBound flag, and
    // $Where supplied from the begin carry. EnableException is bound so Stop-Function's scope-walking default
    // inherits the caller's value.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Path, $Where, $EnableException, $__pathBound, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$Path, [string]$Where, $EnableException, $__pathBound)
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Read-DbaTraceFile
        }

        if ($__pathBound) {
            $currentPath = $path
        } else {
            $currentPath = $server.ConnectionContext.ExecuteScalar("SELECT path FROM sys.traces WHERE is_default = 1")
        }

        foreach ($file in $currentPath) {
            Write-Message -Level Verbose -Message "Parsing $file" -FunctionName Read-DbaTraceFile -ModuleName "dbatools"

            $exists = Test-DbaPath -SqlInstance $server -Path $file

            if (!$exists) {
                Write-Message -Level Warning -Message "Path does not exist" -Target $file -FunctionName Read-DbaTraceFile -ModuleName "dbatools"
                Continue
            }

            $sql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName, ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName, SERVERPROPERTY('ServerName') AS SqlInstance, *
                FROM fn_trace_gettable('$file', DEFAULT)
                $Where"

            Write-Message -Message "SQL: $sql" -Level Debug -FunctionName Read-DbaTraceFile -ModuleName "dbatools"
            try {
                $server.Query($sql)
            } catch {
                Stop-Function -Message "Error returned from SQL Server: $instance" -Target $server -InnerErrorRecord $_ -FunctionName Read-DbaTraceFile
            }
        }
    }
} $SqlInstance $SqlCredential $Path $Where $EnableException $__pathBound @__commonParameters 3>&1 2>&1
""";
}

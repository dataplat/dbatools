#nullable enable

using System;
using System.Collections;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Converts a SQL Server trace (from Get-DbaTrace) into an equivalent Extended Events session using the
/// SQLskills sp_SQLskills_ConvertTraceToEEs conversion script.
/// </summary>
/// <remarks>
/// The trace validation, the version guard, the conversion-script templating, the tempdb execution, and
/// the resulting Get-DbaXESession all run the original dbatools PowerShell body VERBATIM inside the
/// dbatools module scope rather than being reimplemented in C#, so the engine decides the observable
/// details.
///
/// The begin block reads the conversion T-SQL from "$script:PSModuleRoot\bin\sp_SQLskills_ConvertTraceToEEs.sql"
/// (a module-scope path), a once-only computation whose result ($rawsql) rides a sentinel to the process
/// records - Get-Content is I/O and can throw terminating, so it must not be folded into the per-record
/// process.
///
/// $Name is the cross-record carrier (DEF-008): it is a non-pipeline Mandatory parameter, so the source
/// binds it ONCE and the process block's "$Name = ..." conflict-rename reassignments (append -traceid, then
/// -Get-Random) persist into every LATER pipeline record on the function scope. A per-record hop scope
/// would reset it to the bound value, so the C# seeds $Name from a carried value (initialized to the bound
/// Name) and captures the re-emitted value after each record. The source's "$PSBoundParameters.Name" (the
/// FIRST conflict probe) reads the IMMUTABLE originally-bound name, distinct from the mutable $Name, so it
/// is carried separately as $__boundName. The carrier sentinel rides a finally around the foreach, so an
/// early "return" on a LATER array element still carries the $Name mutations an EARLIER element made in the
/// same record (the source keeps $Name on the persistent function scope regardless of the return).
///
/// There is no cross-record interrupt guard in the source (the no-Continue Stop-Functions arm an interrupt
/// nothing reads), so none is carried. $InputObject is value-from-pipeline and only read per record. Each
/// -OutputScriptOnly result string, each conflict Write-Message, and each Get-DbaXESession emit before a
/// later trace may fail under -EnableException, so the process hop uses InvokeScopedStreaming. Surface
/// pinned by migration/baselines/ConvertTo-DbaXESession.json.
/// </remarks>
[Cmdlet(VerbsData.ConvertTo, "DbaXESession")]
public sealed class ConvertToDbaXESessionCommand : DbaBaseCmdlet
{
    /// <summary>The trace object(s) to convert, from Get-DbaTrace.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public object[] InputObject { get; set; } = null!;

    /// <summary>The name for the new Extended Events session.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [PsStringCast]
    public string Name { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 2)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Output the resulting T-SQL instead of creating the session.</summary>
    [Parameter]
    public SwitchParameter OutputScriptOnly { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare, which the inherited
    // [Parameter] already matches; no override needed.

    // The conversion T-SQL, read once in the begin hop and carried to every record.
    private object? _rawSql;

    // The source's function-scope $Name, carried across records (see the class remarks); seeded from the
    // bound Name in BeginProcessing.
    private object? _name;

    protected override void BeginProcessing()
    {
        _name = Name;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__convertToDbaXESessionBegin"))
            {
                if (sentinel["__convertToDbaXESessionBegin"] is Hashtable state)
                {
                    _rawSql = state["RawSql"];
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
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__convertToDbaXESessionProcess"))
            {
                if (sentinel["__convertToDbaXESessionProcess"] is Hashtable state)
                {
                    _name = state["Name"];
                }
                return;
            }
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
            InputObject, _name, Name, SqlCredential, OutputScriptOnly.ToBool(), _rawSql, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block, returning $rawsql via a sentinel. Runs once in BeginProcessing. The source reads
    // the conversion script from $script:PSModuleRoot; the module's script scope is NOT reliably visible
    // inside the nested hop under the gate harness (it resolved EMPTY there, making the path CWD-relative -
    // A's discriminator on W2-252), so the module root is passed in as $__moduleRoot from the already-resolved
    // $__dbatoolsModule.ModuleBase. Same value, resolved through the module object instead of its script scope.
    private const string BeginScript = """
param($__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    $__moduleRoot = (Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1).ModuleBase
    $rawpath = [IO.Path]::Combine($__moduleRoot, "bin", "sp_SQLskills_ConvertTraceToEEs.sql")
    $rawsql = Get-Content $rawpath -Raw
    @{ __convertToDbaXESessionBegin = @{ RawSql = $rawsql } }
} @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM apart from -FunctionName ConvertTo-DbaXESession on the direct
    // Stop-Function/Write-Message sites, $PSBoundParameters.Name -> the immutable $__boundName, the $Name
    // carrier seeded at the top and re-emitted in a sentinel, and $rawsql supplied from the begin carry.
    // EnableException is bound so Stop-Function's scope-walking default inherits the caller's value.
    private const string ProcessScript = """
param($InputObject, $__carriedName, $__boundName, $SqlCredential, $OutputScriptOnly, $rawsql, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([object[]]$InputObject, $__carriedName, [string]$__boundName, $SqlCredential, $OutputScriptOnly, $rawsql, $EnableException)
    # Seed the carried cross-record state of $Name (source keeps it in the shared process scope).
    $Name = $__carriedName
    # The sentinel rides a finally so an early return on a LATER array element still carries the $Name
    # mutations an EARLIER element made (the source keeps $Name on the persistent function scope).
    try {
    foreach ($trace in $InputObject) {
        if (-not $trace.id -and -not $trace.Parent) {
            Stop-Function -Message "Input is of the wrong type. Use Get-DbaTrace." -Continue -FunctionName ConvertTo-DbaXESession
            return
        }

        $server = $trace.Parent

        if ($server.VersionMajor -lt 11) {
            Stop-Function -Message "SQL Server version 2012+ required - $server not supported." -FunctionName ConvertTo-DbaXESession
            return
        }

        $tempdb = $server.Databases['tempdb']
        $traceid = $trace.id

        $splatXESession = @{
            SqlInstance = $server
            Session     = $__boundName
        }
        if ($SqlCredential) {
            $splatXESession["SqlCredential"] = $SqlCredential
        }

        if ((Get-DbaXESession @splatXESession)) {
            $oldname = $name
            $Name = "$name-$traceid"
            Write-Message -Level Output -Message "XE Session $oldname already exists on $server, trying $name." -FunctionName ConvertTo-DbaXESession -ModuleName "dbatools"
        }

        $splatXESession["Session"] = $Name
        if ((Get-DbaXESession @splatXESession)) {
            $oldname = $name
            $Name = "$name-$(Get-Random)"
            Write-Message -Level Output -Message "XE Session $oldname already exists on $server, trying $name." -FunctionName ConvertTo-DbaXESession -ModuleName "dbatools"
        }

        $sql = $rawsql.Replace("--TRACEID--", $traceid)
        $sql = $sql.Replace("--SESSIONNAME--", $name)

        try {
            Write-Message -Level Verbose -Message "Executing SQL in tempdb." -FunctionName ConvertTo-DbaXESession -ModuleName "dbatools"
            $results = $tempdb.ExecuteWithResults($sql).Tables.Rows.SqlString
        } catch {
            Stop-Function -Message "Issue creating, dropping or executing sp_SQLskills_ConvertTraceToExtendedEvents in tempdb on $server." -Target $server -ErrorRecord $_ -FunctionName ConvertTo-DbaXESession
        }

        $results = $results -join [System.Environment]::NewLine

        if ($OutputScriptOnly) {
            $results
        } else {
            Write-Message -Level Verbose -Message "Creating XE Session $name." -FunctionName ConvertTo-DbaXESession -ModuleName "dbatools"
            try {
                $tempdb.ExecuteNonQuery($results)
            } catch {
                Stop-Function -Message "Issue creating extended event $name on $server." -Target $server -ErrorRecord $_ -FunctionName ConvertTo-DbaXESession
            }
            $splatGetSession = @{
                SqlInstance = $server
                Session     = $name
            }
            if ($SqlCredential) {
                $splatGetSession["SqlCredential"] = $SqlCredential
            }
            Get-DbaXESession @splatGetSession
        }
    }
    } finally {
        @{ __convertToDbaXESessionProcess = @{ Name = $Name } }
    }
} $InputObject $__carriedName $__boundName $SqlCredential $OutputScriptOnly $rawsql $EnableException @__commonParameters 3>&1 2>&1
""";
}

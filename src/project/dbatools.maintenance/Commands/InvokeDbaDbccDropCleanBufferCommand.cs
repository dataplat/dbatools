#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Clears the SQL Server buffer pool and columnstore object pool via DBCC DROPCLEANBUFFERS. The
/// begin-block query construction, per-instance connect, ShouldProcess-gated execution, and the
/// per-instance result object remain a module-scoped PowerShell compatibility hop; the compiled
/// cmdlet supplies the begin/process lifetime, routes both ShouldProcess gates through its real
/// runtime (ConfirmImpact High), and carries the function-scoped $results the source leaks across
/// pipeline records. Surface pinned by migration/baselines/Invoke-DbaDbccDropCleanBuffer.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbccDropCleanBuffer", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class InvokeDbaDbccDropCleanBufferCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Suppresses informational messages from the DBCC DROPCLEANBUFFERS command output.</summary>
    [Parameter]
    public SwitchParameter NoInformationalMessages { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // $stringBuilder is built once in the source begin block and read every process record; carry it
    // forward so the process hop reads the same query the begin scope produced.
    private object? _stringBuilder;

    // $results is function-scoped in the source: it is assigned only inside the execute-ShouldProcess
    // gate but read inside the SEPARATE output-ShouldProcess gate. When the execute gate returns false
    // yet the output gate returns true (mixed interactive -Confirm across piped instances), the source
    // reads the PRIOR record's $results; a per-record hop resets it, so we carry it forward to reproduce
    // that leak bug-for-bug. Starts null (never assigned on record 1).
    private object? _resultsState;

    // Per-invocation token so the process carrier sentinel is distinguishable from real output.
    private readonly string _processToken = Guid.NewGuid().ToString("N");

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            TestBound(nameof(NoInformationalMessages)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__InvokeDbaDbccDropCleanBufferBeginComplete"]?.Value))
            {
                _stringBuilder = UnwrapHopValue(item.Properties["StringBuilder"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && string.Equals(
                item.Properties["__InvokeDbaDbccDropCleanBufferProcessComplete"]?.Value as string, _processToken, StringComparison.Ordinal))
            {
                _resultsState = UnwrapHopValue(item.Properties["Results"]?.Value);
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            _stringBuilder, SqlInstance, SqlCredential, EnableException.ToBool(), _resultsState, this, _processToken,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // Carried hop state arrives PSObject-wrapped. A PSCustomObject carries its content on the
    // wrapper rather than the BaseObject, so unwrapping one would discard it - keep it wrapped.
    private static object? UnwrapHopValue(object? value)
    {
        if (value is PSObject wrapper && wrapper.BaseObject is not PSCustomObject)
            return wrapper.BaseObject;
        return value;
    }

    private const string BeginScript = """
param($__boundNoInformationalMessages, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__boundNoInformationalMessages)

    $stringBuilder = New-Object System.Text.StringBuilder
    $null = $stringBuilder.Append("DBCC DROPCLEANBUFFERS")
    # Test-Bound replacement: the source keyed the WITH NO_INFOMSGS suffix off whether the caller
    # explicitly bound this switch (a boundness check, not its value); module scope cannot see the
    # caller's bound set, so boundness is carried in as a flag.
    if ($__boundNoInformationalMessages) {
        $null = $stringBuilder.Append(" WITH NO_INFOMSGS")
    }

    [pscustomobject]@{ __InvokeDbaDbccDropCleanBufferBeginComplete = $true; StringBuilder = $stringBuilder }
} $__boundNoInformationalMessages @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = """
param($StringBuilder, $SqlInstance, $SqlCredential, $EnableException, $results, $__realCmdlet, $__processToken, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param($StringBuilder, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, $EnableException, $results, $__realCmdlet, $__processToken)

    $query = $StringBuilder.ToString()

    foreach ($instance in $SqlInstance) {
        Write-Message -Message "Attempting Connection to $instance" -Level Verbose -FunctionName Invoke-DbaDbccDropCleanBuffer -ModuleName "dbatools"
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaDbccDropCleanBuffer
        }

        try {
            if ($__realCmdlet.ShouldProcess($server.Name, "Execute the command $query against $instance")) {
                Write-Message -Message "Query to run: $query" -Level Verbose -FunctionName Invoke-DbaDbccDropCleanBuffer -ModuleName "dbatools"
                $results = $server | Invoke-DbaQuery  -Query $query -MessagesToOutput
            }
        } catch {
            Stop-Function -Message "Failure running DBCC DROPCLEANBUFFERS" -ErrorRecord $_ -Target $server -Continue -FunctionName Invoke-DbaDbccDropCleanBuffer
        }
        If ($__realCmdlet.ShouldProcess("console", "Outputting object")) {
            [PSCustomObject]@{
                ComputerName = $server.ComputerName
                InstanceName = $server.ServiceName
                SqlInstance  = $server.DomainInstanceName
                Cmd          = $query.ToString()
                Output       = $results
            }
        }
    }

    [pscustomobject]@{ __InvokeDbaDbccDropCleanBufferProcessComplete = $__processToken; Results = $results }
} $StringBuilder $SqlInstance $SqlCredential $EnableException $results $__realCmdlet $__processToken @__commonParameters 3>&1 2>&1
""";
}

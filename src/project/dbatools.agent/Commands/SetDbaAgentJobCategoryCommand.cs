#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Renames SQL Server Agent job categories.
/// </summary>
/// <remarks>
/// The instance connection, the category existence/collision validation, the Rename, and the output all
/// run the original dbatools PowerShell body inside the dbatools module scope rather than being
/// reimplemented in C#, so the engine decides the observable details.
///
/// The function has begin/process/end blocks. The begin block runs a one-shot guard (renaming several
/// categories to a single name) whose Stop-Function has no -Continue, so it sets the function-scope
/// interrupt and returns; every process record then short-circuits via Test-FunctionInterrupt. That
/// interrupt does not survive between hops on its own (Stop-Function writes it at -Scope 1 of the begin
/// hop's own scriptblock), so the begin hop reads it with Get-Variable -Scope 0 after a dot-sourced body
/// and reports it in a sentinel; the C# field then guards ProcessRecord. Under -EnableException that begin
/// Stop-Function throws instead, terminating the cmdlet before any record. The process Stop-Functions all
/// use -Continue (which per Stop-Function never sets the interrupt), so no process record re-reports it.
/// The end block is a bare Verbose line that the source runs even when interrupted (a non-EnableException
/// interrupt only 'return's from begin, it does not terminate), so EndProcessing is guarded only by the
/// C# stop flag, NOT by the begin interrupt.
///
/// The begin block's "if (\$Force) { \$ConfirmPreference = 'none' }" is folded into the top of the process
/// hop (where ShouldProcess reads the confirm preference), because -Force is not pipeline-bound and setting
/// it in the separate begin hop scope would not reach process; the gate then routes to \$PSCmdlet (which
/// reads the hop scope's lowered preference) under -Force, else to the outer cmdlet's real ShouldProcess.
///
/// Output streams: each renamed category is emitted (via Get-DbaAgentJobCategory) before a later one may
/// fail under -EnableException, so the process hop streams. Surface pinned by
/// migration/baselines/Set-DbaAgentJobCategory.json.
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaAgentJobCategory", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class SetDbaAgentJobCategoryCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The existing job category name(s) to rename.</summary>
    [Parameter(Position = 2)]
    [ValidateNotNullOrEmpty]
    public string[]? Category { get; set; }

    /// <summary>The new name(s) for the job category.</summary>
    [Parameter(Position = 3)]
    public string[]? NewName { get; set; }

    /// <summary>Bypass the confirmation prompt.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which the
    // inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    // The function-scope interrupt set by the begin block's no-Continue Stop-Function; carried to guard the
    // process records (Stop-Function writes it in the begin hop's scope, which dies with that hop).
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Category, NewName, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__setDbaAgentJobCategoryBegin"))
            {
                if (sentinel["__setDbaAgentJobCategoryBegin"] is Hashtable state)
                {
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
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
        if (Interrupted || _interrupted)
        {
            return;
        }

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
            SqlInstance, SqlCredential, Category, NewName, Force.ToBool(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
    {
        // NOT guarded by _interrupted: the source's end block runs even after a non-EnableException begin
        // interrupt (that interrupt only 'return's from begin; it does not terminate the pipeline).
        if (Interrupted)
        {
            return;
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, EndScript,
            EnableException.ToBool(),
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

    // PS: the begin block VERBATIM apart from -FunctionName Set-DbaAgentJobCategory on the direct
    // Stop-Function. The "if (\$Force) { \$ConfirmPreference = 'none' }" line is folded into the process hop
    // (it has no effect in begin - nothing reads the preference there). The body is dot-sourced so the
    // guard's "+ return" exits only the block; then the interrupt flag is read at Get-Variable -Scope 0 and
    // reported in a sentinel.
    private const string BeginScript = """
param($Category, $NewName, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string[]]$Category, [string[]]$NewName, $EnableException)
    . {
        # Check if multiple categories are being changed
        if ($Category.Count -gt 1 -and $NewName.Count -eq 1) {
            Stop-Function -Message "You cannot rename multiple jobs to the same name" -FunctionName Set-DbaAgentJobCategory
            return
        }
    }
    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __setDbaAgentJobCategoryBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $Category $NewName $EnableException @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM apart from $PSCmdlet.ShouldProcess -> $__gate.ShouldProcess and
    // -FunctionName Set-DbaAgentJobCategory on the direct Stop-Function/Write-Message sites. The begin's
    // Force/ConfirmPreference line and the gate selection are prepended (folded from begin). The
    // Test-FunctionInterrupt check is preserved for fidelity but is inert here - the C# ProcessRecord guard
    // already short-circuits an interrupted record (the interrupt does not survive into this fresh hop scope).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Category, $NewName, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$Category, [string[]]$NewName, $Force, $EnableException, $__realCmdlet)

    if ($Force) { $ConfirmPreference = 'none' }
    $__gate = if ($Force) { $PSCmdlet } else { $__realCmdlet }
    if (Test-FunctionInterrupt) { return }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaAgentJobCategory
        }

        # Loop through each of the categories
        foreach ($cat in $Category) {
            # Check if the category exists
            if ($cat -notin $server.JobServer.JobCategories.Name) {
                Stop-Function -Message "Job category $cat doesn't exist on $instance" -Target $instance -Continue -FunctionName Set-DbaAgentJobCategory
            }

            # Check if the category already exists
            if ($NewName -and ($NewName -in $server.JobServer.JobCategories.Name)) {
                Stop-Function -Message "Job category $NewName already exists on $instance" -Target $instance -Continue -FunctionName Set-DbaAgentJobCategory
            }

            if ($__gate.ShouldProcess($instance, "Changing the job category $Category")) {
                try {
                    # Get the job category object
                    $currentCategory = $server.JobServer.JobCategories[$cat]

                    Write-Message -Message "Changing job category $cat" -Level Verbose -FunctionName Set-DbaAgentJobCategory -ModuleName "dbatools"

                    # Get and set the original and new values
                    $newCategoryName = $null

                    # Check if the job category needs to be renamed
                    if ($NewName) {
                        $currentCategory.Rename($NewName[$Category.IndexOf($cat)])
                        $newCategoryName = $currentCategory.Name
                    }

                    Get-DbaAgentJobCategory -SqlInstance $server -Category $newCategoryName
                } catch {
                    Stop-Function -Message "Something went wrong changing the job category $cat on $instance" -Target $cat -Continue -ErrorRecord $_ -FunctionName Set-DbaAgentJobCategory
                }
            }
        }
    }
} $SqlInstance $SqlCredential $Category $NewName $Force $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM apart from -FunctionName Set-DbaAgentJobCategory on the direct Write-Message.
    // $EnableException is marshaled in (as in the source's function scope) so Write-Message's scope-walking
    // default has it, and it gives the hop a positional arg to align.
    private const string EndScript = """
param($EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($EnableException)
    Write-Message -Message "Finished changing job category." -Level Verbose -FunctionName Set-DbaAgentJobCategory -ModuleName "dbatools"
} $EnableException @__commonParameters 3>&1 2>&1
""";
}

#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Returns the next value from a sequence. Port of public/Select-DbaDbSequenceNextValue.ps1; the
/// workflow remains a module-scoped PowerShell compatibility hop.
///
/// The source declares SupportsShouldProcess but never calls ShouldProcess anywhere in its body, so
/// nothing is gated and neither -WhatIf nor -Confirm suppresses anything. That is preserved rather
/// than corrected: the attribute stays, because it is part of the command's parameter surface and
/// removing it would drop -WhatIf and -Confirm from the baseline, and no gate is introduced, because
/// adding one would stop the command doing work the script function does. There is consequently no
/// $Pscmdlet call to route to the outer cmdlet on this row.
///
/// Test-Bound cannot ride the hop - inside one the caller is the scriptblock, not this cmdlet - so
/// all three call sites are flag-substituted and evaluated here.
///
/// -SqlInstance and -InputObject are SCALARS on this command, not arrays, so there is no instance
/// loop and the per-element hop question does not arise; the hop runs once per pipeline record.
///
/// No local needs a cross-record carry. The body assigns $InputObject from Get-DbaDatabase when
/// -SqlInstance was supplied, but $InputObject is re-bound from the pipeline on every record before
/// that runs, so the assignment cannot leak forward.
///
/// No graceful-stop latch: the source has no Test-FunctionInterrupt guard, so a later record
/// re-enters the process body and re-evaluates the guard, warning again - carrying a latch would
/// suppress warnings the function repeats.
///
/// The hop streams rather than buffers, so a caller piping into Select-Object -First N stops the
/// upstream sequence reads instead of running them all first.
/// </summary>
[Cmdlet(VerbsCommon.Select, "DbaDbSequenceNextValue", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(PSObject))]
public sealed class SelectDbaDbSequenceNextValueCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database holding the sequence.</summary>
    [Parameter(Position = 2)]
    public string? Database { get; set; }

    /// <summary>The sequence to read the next value from.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [Alias("Name")]
    public string[]? Sequence { get; set; }

    /// <summary>The schema holding the sequence.</summary>
    [Parameter(Position = 4)]
    public string Schema { get; set; } = "dbo";

    /// <summary>An SMO database object, typically from Get-DbaDatabase.</summary>
    [Parameter(Position = 5, ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.Database? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

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
                return;
            }
            WriteObject(item);
        }, BodyScript,
            SqlInstance, SqlCredential, Database, Sequence, Schema, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(Database)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source's process body VERBATIM. Substitutions only: the three Test-Bound call sites
    // -> flags computed on the C# side, and -FunctionName on Stop-Function.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $Sequence, $Schema, $InputObject, $EnableException, $__boundSqlInstance, $__boundDatabase, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [PSCredential]$SqlCredential, [string]$Database, [string[]]$Sequence, [string]$Schema, [Microsoft.SqlServer.Management.Smo.Database]$InputObject, $EnableException, $__boundSqlInstance, $__boundDatabase, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }


        if ($__boundSqlInstance -and (-not $__boundDatabase)) {
            Stop-Function -Message "Database is required when SqlInstance is specified" -FunctionName Select-DbaDbSequenceNextValue
            return
        }

        if ($__boundSqlInstance) {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        $InputObject.Query("SELECT NEXT VALUE FOR [$($Schema)].[$($Sequence)] AS NextValue").NextValue

} $SqlInstance $SqlCredential $Database $Sequence $Schema $InputObject $EnableException $__boundSqlInstance $__boundDatabase $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

#nullable enable

using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Deprecation stub. Port of public/Update-Dbatools.ps1 (W1-042): the entire function body
/// is one unconditional Write-Warning in a BLOCKLESS body (END-block semantics - the W1-012
/// precedent), so the warning fires once in EndProcessing regardless of -WhatIf (no
/// ShouldProcess call exists to gate it) or the bound switches.
/// Surface pinned by migration/baselines/Update-Dbatools.json.
/// </summary>
[Cmdlet(VerbsData.Update, "Dbatools", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class UpdateDbatoolsCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared. The function has
    // the parameter but never reads it (nothing here calls Stop-Function).

    [Parameter]
    [Alias("dev", "devbranch")]
    public SwitchParameter Development { get; set; }

    [Parameter]
    public SwitchParameter Cleanup { get; set; }

    protected override void EndProcessing()
    {
        WriteWarning("This command is deprecated. Please use PowerShell's built-in commands, Install-Module and Update-Module, instead.");
    }
}

#nullable enable

using System.Management.Automation;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Returns a fresh SMO ScriptingOptions object for customizing Export-DbaScript and
/// friends. Port of public/New-DbaScriptingOption.ps1 (W1-029) - the function body is a
/// single New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions. The function is
/// a SIMPLE function (no CmdletBinding), so the compiled cmdlet's common parameters and
/// inherited EnableException are the standing additive-surface ruling.
/// Surface pinned by migration/baselines/New-DbaScriptingOption.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaScriptingOption")]
public sealed class NewDbaScriptingOptionCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void EndProcessing()
    {
        WriteObject(new ScriptingOptions());
    }
}

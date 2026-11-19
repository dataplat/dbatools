#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Opens the dbatools release changelog in the default browser. Port of
/// public/Get-DbatoolsChangeLog.ps1: the Start-Process call rides the REAL engine cmdlet
/// through NestedCommand (default-browser resolution, ambient WhatIf behavior and error
/// records are the engine's own), the deprecated -Local branch keeps its Write-Message
/// warning. The function body had no begin/process/end blocks, so it ran in the END block;
/// EndProcessing preserves that (piped input is rejected by the binder exactly like the
/// advanced function rejected it - no pipeline-bindable parameters). Surface pinned by
/// migration/baselines/Get-DbatoolsChangeLog.json (Local + EnableException, single set).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbatoolsChangeLog")]
[OutputType(typeof(void))]
public sealed class GetDbatoolsChangeLogCommand : DbaBaseCmdlet
{
    /// <summary>Deprecated: the changelog is only available online.</summary>
    [Parameter]
    public SwitchParameter Local { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void EndProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        try
        {
            if (!Local.IsPresent)
            {
                Hashtable splatStart = new();
                splatStart["FilePath"] = "https://github.com/dataplat/dbatools/releases";
                NestedCommand.Invoke(this, "Start-Process", splatStart);
            }
            else
            {
                WriteMessage(MessageLevel.Warning, "Sorry, changelog is only available online");
            }
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (RuntimeException rex)
        {
            StopFunction("Failure", errorRecord: rex.ErrorRecord);
            return;
        }
        catch (Exception ex)
        {
            StopFunction("Failure", exception: ex);
            return;
        }
    }
}

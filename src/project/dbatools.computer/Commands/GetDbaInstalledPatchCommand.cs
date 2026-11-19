#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves installed SQL Server patches (hotfixes, service packs, GDRs) from the uninstall
/// registry of target computers. Port of public/Get-DbaInstalledPatch.ps1; surface pinned by
/// migration/baselines/Get-DbaInstalledPatch.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaInstalledPatch")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaInstalledPatchCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Alternate credential for connecting to the remote computer.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The Invoke-Command2 scriptblock (cooked, no -Raw), verbatim from the PS source.
    private const string PatchScript = @"
                    Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall | Get-ItemProperty | Where-Object { $_.DisplayName -like ""Hotfix*SQL*"" -or $_.DisplayName -like ""Service Pack*SQL*"" -or $_.DisplayName -like ""GDR*SQL*"" } | Sort-Object InstallDate
                ";

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (ComputerName is null)
        {
            return;
        }

        // PS: foreach ($computer in $ComputerName.ComputerName) - member enumeration yields the
        // ComputerName strings.
        foreach (DbaInstanceParameter computerParam in ComputerName)
        {
            if (computerParam is null)
            {
                continue;
            }
            string computer = computerParam.ComputerName;

            object? patches;
            try
            {
                RemoteExecutionService.RemoteCommandRequest request = new()
                {
                    ComputerName = new DbaInstanceParameter(computer),
                    Credential = Credential,
                    ScriptText = PatchScript
                };
                RemoteExecutionService.RemoteCommandResult result = RemoteExecutionService.InvokeCommand(this, request);
                foreach (ErrorRecord error in result.Errors)
                {
                    WriteError(NestedCommand.PreserveErrorIdentity(error));
                }
                patches = ShapeOutput(result.Output);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException rex)
            {
                StopFunction("Failed", target: computer, errorRecord: rex.ErrorRecord, continueLoop: true);
                continue;
            }
            catch (Exception ex)
            {
                StopFunction("Failed", target: computer, exception: ex, continueLoop: true);
                continue;
            }

            if (patches is null)
            {
                continue;
            }

            foreach (object patch in EnumeratePipeline(patches))
            {
                PSObject patchObject = PSObject.AsPSObject(patch);
                try
                {
                    // PS: InstallDate = [DbaDate][datetime]::ParseExact($patch.InstallDate,
                    //     'yyyyMMdd', $null) - a malformed date makes the whole emission
                    //     statement fail for that patch; the loop moves on.
                    string installDateRaw = LanguagePrimitives.ConvertTo<string>(patchObject.Properties["InstallDate"]?.Value);
                    DbaDate installDate = new DbaDate(DateTime.ParseExact(installDateRaw, "yyyyMMdd", CultureInfo.CurrentCulture));

                    PSObject output = new();
                    output.Properties.Add(new PSNoteProperty("ComputerName", computer));
                    output.Properties.Add(new PSNoteProperty("Name", patchObject.Properties["DisplayName"]?.Value));
                    output.Properties.Add(new PSNoteProperty("Version", patchObject.Properties["DisplayVersion"]?.Value));
                    output.Properties.Add(new PSNoteProperty("InstallDate", installDate));
                    WriteObject(output);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    WriteError(new ErrorRecord(ex, "dbatools_Get-DbaInstalledPatch", ErrorCategory.NotSpecified, patch));
                }
            }
        }
    }

    // PS pipeline-assignment shape: empty -> null, one -> the scalar, many -> object[].
    private static object? ShapeOutput(List<PSObject> output)
    {
        if (output.Count == 0)
        {
            return null;
        }
        if (output.Count == 1)
        {
            return output[0];
        }
        return output.ToArray();
    }

    // PS: foreach over a shaped value - a scalar iterates once, an array element-wise.
    private static IEnumerable<object> EnumeratePipeline(object value)
    {
        if (value is object[] many)
        {
            foreach (object item in many)
            {
                if (item is not null)
                {
                    yield return item;
                }
            }
        }
        else
        {
            yield return value;
        }
    }

    // PS: [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME
    private static DbaInstanceParameter[]? DefaultComputerName()
    {
        string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(machine))
        {
            return null;
        }
        return new[] { new DbaInstanceParameter(machine) };
    }
}

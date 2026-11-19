#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets an instance's default Data/Log/Backup paths. Port of public/Set-DbaDefaultPath.ps1
/// (W1-036). Per instance: the family-standard ConnectInstance (AzureUnsupported) with the
/// Stop-Function -Continue failure shape; the bound Path trims trailing backslashes ONCE per
/// record like the function's in-place reassignment; accessibility rides the REAL (still-PS)
/// Test-DbaPath through the module-scope hop with the live server object; each -Type match
/// (PS -contains = case-insensitive against the ValidateSet-normalized input) sets its SMO
/// property under its own Medium-impact ShouldProcess; the commit gate Alters, warns the
/// restart requirement when Data or Log changed (interpolating the DbaInstanceParameter
/// PS-style), and emits the six-property result. An Alter fault surfaces as the PS
/// method-invocation wrap through the function's exact Stop-Function -Continue site.
/// Positions 0-3 pin the PS implicit positional binding.
/// Surface pinned by migration/baselines/Set-DbaDefaultPath.json.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDefaultPath", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class SetDbaDefaultPathCommand : DbaInstanceCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    [Parameter(ValueFromPipelineByPropertyName = true, Position = 2)]
    [ValidateSet("Data", "Backup", "Log")]
    public string[]? Type { get; set; }

    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, Position = 3)]
    [PsStringCast]
    public string Path { get; set; } = null!;

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported }
            // catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
                continue;

            // PS: $Path = $Path.Trim().TrimEnd("\")
            string path = Path.Trim().TrimEnd('\\');

            // PS: if (-not (Test-DbaPath -SqlInstance $server -Path $Path)) { Stop-Function ... -Continue }
            // PS collection truthiness: empty = false, one item = that item's truthiness,
            // several items = true regardless of contents (codex r1).
            System.Collections.ObjectModel.Collection<PSObject> pathResults = NestedCommand.InvokeScoped(this, TestDbaPathScript, server, path);
            bool accessible = pathResults.Count > 1 ||
                (pathResults.Count == 1 && LanguagePrimitives.IsTrue(PsAssignment.Unwrap(pathResults[0])));
            if (!accessible)
            {
                StopFunction("Path " + path + " is not accessible on " + server.Name, target: instance, continueLoop: true);
                continue;
            }

            bool wantsData = TypeContains("Data");
            bool wantsLog = TypeContains("Log");

            if (wantsData)
            {
                // PS: if ($Pscmdlet.ShouldProcess($server.Name, "Changing DefaultFile to $Path"))
                if (ShouldProcess(server.Name, "Changing DefaultFile to " + path))
                    server.DefaultFile = path;
            }

            if (wantsLog)
            {
                if (ShouldProcess(server.Name, "Changing DefaultLog to " + path))
                    server.DefaultLog = path;
            }

            if (TypeContains("Backup"))
            {
                if (ShouldProcess(server.Name, "Changing BackupDirectory to " + path))
                    server.BackupDirectory = path;
            }

            // PS: if ($Pscmdlet.ShouldProcess($server.Name, "Committing changes"))
            if (ShouldProcess(server.Name, "Committing changes"))
            {
                try
                {
                    try
                    {
                        server.Alter();
                    }
                    catch (Exception alterFault)
                    {
                        throw WrapAsMethodInvocation(alterFault, "Alter", 0);
                    }

                    if (wantsData || wantsLog)
                    {
                        // PS: Write-Message -Level Warning -Message "You must restart the SQL Service on $instance for changes to take effect"
                        WriteMessageWarning("You must restart the SQL Service on " + PSObject.AsPSObject(instance).ToString() + " for changes to take effect");
                    }

                    PSObject output = new PSObject();
                    output.Properties.Add(new PSNoteProperty("ComputerName", SmoServerExtensions.GetPSProperty(server, "ComputerName")));
                    output.Properties.Add(new PSNoteProperty("InstanceName", server.ServiceName));
                    output.Properties.Add(new PSNoteProperty("SqlInstance", SmoServerExtensions.GetDomainInstanceName(server)));
                    output.Properties.Add(new PSNoteProperty("Data", server.DefaultFile));
                    output.Properties.Add(new PSNoteProperty("Log", server.DefaultLog));
                    output.Properties.Add(new PSNoteProperty("Backup", server.BackupDirectory));
                    WriteObject(output);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    // PS: catch { Stop-Function -Message "Error occurred while committing changes to $instance" -ErrorRecord $_ -Target $instance -Continue }
                    StopFunction("Error occurred while committing changes to " + PSObject.AsPSObject(instance).ToString(),
                        target: instance, errorRecord: ToCaughtRecord(ex), continueLoop: true);
                    continue;
                }
            }
        }
    }

    /// <summary>PS: $Type -contains "X" - case-insensitive membership; a null Type never matches.</summary>
    private bool TypeContains(string value)
    {
        if (Type is null)
            return false;
        foreach (string? element in Type)
        {
            if (PsString.Eq(element, value))
                return true;
        }
        return false;
    }

    /// <summary>Write-Message -Level Warning: displays AND reaches an enclosing
    /// -WarningVariable, never throws (EnableException does not affect Write-Message).</summary>
    private void WriteMessageWarning(string message)
    {
        WriteMessage(MessageLevel.Warning, message);
    }

    /// <summary>Rebuilds the MethodInvocationException the PS method binder raised for a
    /// failed .NET call: 'Exception calling "Name" with "N" argument(s): "inner"'.</summary>
    private static MethodInvocationException WrapAsMethodInvocation(Exception inner, string methodName, int argumentCount)
    {
        string text = "Exception calling \"" + methodName + "\" with \"" + argumentCount + "\" argument(s): \"" + inner.Message + "\"";
        return new MethodInvocationException(text, inner);
    }

    /// <summary>PS: catch { $_ } - a hand-built RuntimeException's lazy record drops the
    /// inner chain (ParentContainsErrorRecordException), so that shape rebuilds.</summary>
    private static ErrorRecord ToCaughtRecord(Exception ex)
    {
        if (ex is RuntimeException runtime && runtime.ErrorRecord is not null &&
            runtime.ErrorRecord.Exception is not ParentContainsErrorRecordException)
        {
            return runtime.ErrorRecord;
        }
        return new ErrorRecord(ex, "Set-DbaDefaultPath", ErrorCategory.NotSpecified, null);
    }

    private const string TestDbaPathScript = """
param($server, $path)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($server, $path)
    Test-DbaPath -SqlInstance $server -Path $path 3>&1
} $server $path
""";
}

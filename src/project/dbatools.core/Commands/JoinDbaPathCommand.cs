#nullable enable

using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Constructs file paths with the separator conventions of the local machine or a target
/// SQL Server instance's host OS. Port of public/Join-DbaPath.ps1; the private
/// Test-HostOSLinux probe runs in the dbatools module scope (it connects via
/// Connect-DbaInstance and matches @@VERSION). Surface pinned by
/// migration/baselines/Join-DbaPath.json (Path position 0, Child remaining-arguments).
/// The function is blockless, so the body runs in END scope.
/// </summary>
[Cmdlet(VerbsCommon.Join, "DbaPath")]
public sealed class JoinDbaPathCommand : DbaBaseCmdlet
{
    /// <summary>The base path to build on.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [PsStringCast]
    public string Path { get; set; } = null!;

    /// <summary>Optional -- tests to see if destination SQL Server is Linux or Windows.</summary>
    [Parameter]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Additional path segments to append (binds remaining arguments).</summary>
    [Parameter(ValueFromRemainingArguments = true)]
    [Alias("ChildPath")]
    public string[]? Child { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void EndProcessing()
    {
        string separator = System.IO.Path.DirectorySeparatorChar.ToString();

        if (!LanguagePrimitives.IsTrue(SqlInstance))
        {
            // PS: return @($path) + $Child -join <sep> -replace '\\|/', <sep>
            // (precedence: join first, then the replace over the joined string).
            // An unbound $Child is $null, and array + $null APPENDS one null element,
            // so the childless join carries a trailing separator (lab-proven).
            List<string> parts = new();
            parts.Add(Path);
            if (Child is null)
                parts.Add("");
            else
                parts.AddRange(Child);
            string joined = string.Join(separator, parts);
            WriteObject(Regex.Replace(joined, "\\\\|/", separator));
            return;
        }

        string resultingPath = Path;

        if (TestHostOSLinux())
        {
            WriteMessage(MessageLevel.Verbose, "Linux detected on remote server");
            resultingPath = resultingPath.Replace("\\", "/");

            if (Child is not null)
            {
                foreach (string childItem in Child)
                    resultingPath = resultingPath + "/" + childItem;
            }
        }
        else
        {
#if NETFRAMEWORK
            // PS 5.1: $PSVersionTable.PSVersion.Major -ge 6 is always false.
            resultingPath = resultingPath.Replace("/", "\\");
#else
            // PS 7+: branch on the module's live $script:isWindows flag like the function
            // (it reads blank under some harnesses - parity requires the same live read).
            if (!LanguagePrimitives.IsTrue(GetModuleVariable("isWindows")))
                resultingPath = resultingPath.Replace("\\", "/");
            else
                resultingPath = resultingPath.Replace("/", "\\");
#endif

            if (Child is not null)
            {
                foreach (string childItem in Child)
                    resultingPath = System.IO.Path.Combine(resultingPath, childItem);
            }
        }

        WriteObject(resultingPath);
    }

    /// <summary>PS: Test-HostOSLinux -SqlInstance $SqlInstance - the PRIVATE probe runs in
    /// the dbatools module scope; its Connect-DbaInstance failure propagates terminating,
    /// exactly like the function's unguarded call.</summary>
    private bool TestHostOSLinux()
    {
        NestedCommand.RequireDbatoolsScriptModule(this);
        Hashtable probeParams = new();
        probeParams["SqlInstance"] = SqlInstance;
        ScriptBlock script = ScriptBlock.Create(
            "param($__cmd, $__params) & (Get-Module dbatools | Where-Object ModuleType -eq \"Script\" | Select-Object -First 1) { param($c, $p) & $c @p } $__cmd $__params");
        Collection<PSObject> result = InvokeCommand.InvokeScript(true, script, null, "Test-HostOSLinux", probeParams);
        object? value = result.Count == 0 ? null : result.Count == 1 ? result[0] : (object)result;
        return LanguagePrimitives.IsTrue(value);
    }

    /// <summary>Reads a $script:-scoped variable LIVE off the dbatools script module.</summary>
    private object? GetModuleVariable(string variableName)
    {
        Hashtable getModuleParams = new();
        getModuleParams["Name"] = "dbatools";
        foreach (PSObject wrapped in NestedCommand.Invoke(this, "Get-Module", getModuleParams))
        {
            if (wrapped?.BaseObject is PSModuleInfo module && module.ModuleType == ModuleType.Script)
                return module.SessionState.PSVariable.GetValue("script:" + variableName);
        }
        return null;
    }
}

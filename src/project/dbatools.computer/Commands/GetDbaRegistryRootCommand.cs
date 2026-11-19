#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves the SQL Server registry root path for each instance on the target computers via
/// SQL WMI. Port of public/Get-DbaRegistryRoot.ps1; surface pinned by
/// migration/baselines/Get-DbaRegistryRoot.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaRegistryRoot")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaRegistryRootCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Alternate credential for connecting to the remote computer.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

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

        foreach (DbaInstanceParameter computer in ComputerName)
        {
            if (computer is null)
            {
                continue;
            }

            // PS: $sqlwmis = Invoke-ManagedComputerCommand -ComputerName $computer.ComputerName
            //     -ScriptBlock { $wmi.Services } -Credential $Credential -ErrorAction Stop |
            //     Where-Object DisplayName -Match "SQL Server \(" - the PRIVATE function runs in
            //     the dbatools module scope (Script-module instance per the W5-017 duplicate rule).
            List<PSObject> sqlwmis = new();
            try
            {
                Hashtable payload = new Hashtable
                {
                    { "ComputerName", computer.ComputerName },
                    { "ScriptText", " $wmi.Services " },
                    { "Credential", Credential }
                };
                NestedCommand.RequireDbatoolsScriptModule(this);
                Collection<PSObject> services = InvokeModuleScoped(
                    "param($__p) " +
                    "$__module = Get-Module dbatools | Where-Object ModuleType -eq \"Script\" | Select-Object -First 1; " +
                    "& $__module { param($p) Invoke-ManagedComputerCommand -ComputerName $p.ComputerName -ScriptBlock ([ScriptBlock]::Create($p.ScriptText)) -Credential $p.Credential -ErrorAction Stop } $__p 3>&1",
                    payload);
                foreach (PSObject service in services)
                {
                    string display = LanguagePrimitives.ConvertTo<string>(service?.Properties["DisplayName"]?.Value) ?? string.Empty;
                    if (System.Text.RegularExpressions.Regex.IsMatch(display, "SQL Server \\(", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                    {
                        sqlwmis.Add(service!);
                    }
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException rex)
            {
                // PS: Stop-Function -Message $_ -Target $sqlwmi -Continue - the MESSAGE is the
                // stringified error record; $sqlwmi is never assigned at that point (null target).
                StopFunction(rex.ErrorRecord?.ToString() ?? rex.Message, errorRecord: rex.ErrorRecord, continueLoop: true);
                continue;
            }
            catch (Exception ex)
            {
                StopFunction(ex.Message, exception: ex, continueLoop: true);
                continue;
            }

            foreach (PSObject sqlwmi in sqlwmis)
            {
                // PS: $regRoot = ($sqlwmi.AdvancedProperties | Where-Object Name -EQ REGROOT).Value
                object? advanced = sqlwmi.Properties["AdvancedProperties"]?.Value;
                string? regRoot = LanguagePrimitives.ConvertTo<string>(GetWhereValue(advanced, "Name", "REGROOT", "Value"));
                string? vsname = LanguagePrimitives.ConvertTo<string>(GetWhereValue(advanced, "Name", "VSNAME", "Value"));
                // PS: $instanceName = $sqlwmi.DisplayName.Replace('SQL Server (', '').Replace(')', '') # Don't clown, I don't know regex :(
                string display = LanguagePrimitives.ConvertTo<string>(sqlwmi.Properties["DisplayName"]?.Value) ?? string.Empty;
                string instanceName = display.Replace("SQL Server (", "").Replace(")", "");

                if (string.IsNullOrEmpty(regRoot))
                {
                    // PS fallback: -match over the stringified AdvancedProperties, then
                    // ($x -Split 'Value\=')[1].
                    string? regRootMatch = null, vsnameMatch = null;
                    foreach (object item in EnumerateCollection(advanced))
                    {
                        string text = item?.ToString() ?? string.Empty;
                        if (text.IndexOf("REGROOT", StringComparison.OrdinalIgnoreCase) >= 0)
                        {
                            regRootMatch = text;
                        }
                        if (text.IndexOf("VSNAME", StringComparison.OrdinalIgnoreCase) >= 0)
                        {
                            vsnameMatch = text;
                        }
                    }

                    if (!string.IsNullOrEmpty(regRootMatch))
                    {
                        regRoot = SplitAfterValue(regRootMatch);
                        vsname = SplitAfterValue(vsnameMatch);
                    }
                    else
                    {
                        // PS: Stop-Function "Can't find instance $instanceName on $env:COMPUTERNAME"
                        // -Continue - the CLIENT machine's env, exactly like the source.
                        StopFunction($"Can't find instance {instanceName} on {Environment.GetEnvironmentVariable("COMPUTERNAME")}", continueLoop: true);
                        continue;
                    }
                }

                // vsname is the virtual server name for a failover cluster instance
                string sqlInstance = string.IsNullOrEmpty(vsname) ? computer.ComputerName : vsname!;
                if (!string.Equals(instanceName, "MSSQLSERVER", StringComparison.OrdinalIgnoreCase))
                {
                    sqlInstance = $"{sqlInstance}\\{instanceName}";
                }

                WriteMessage(MessageLevel.Verbose, $"Regroot: {regRoot}");
                WriteMessage(MessageLevel.Verbose, $"InstanceName: {instanceName}");
                WriteMessage(MessageLevel.Verbose, $"VSNAME: {vsname}");

                PSObject output = new();
                output.Properties.Add(new PSNoteProperty("ComputerName", computer.ComputerName));
                output.Properties.Add(new PSNoteProperty("InstanceName", instanceName));
                output.Properties.Add(new PSNoteProperty("SqlInstance", sqlInstance));
                output.Properties.Add(new PSNoteProperty("Hive", "HKLM"));
                output.Properties.Add(new PSNoteProperty("Path", regRoot));
                output.Properties.Add(new PSNoteProperty("RegistryRoot", $"HKLM:\\{regRoot}"));
                WriteObject(output);
            }
        }
    }

    // NestedCommand discipline for module-scoped private-function calls: PSDPV shield plus 3>&1
    // warning re-emit through this cmdlet's stream.
    private Collection<PSObject> InvokeModuleScoped(string scriptText, object payload)
    {
        object? effective = SessionState.PSVariable.GetValue("PSDefaultParameterValues");
        // Module-internal calls resolve $PSDefaultParameterValues from the MODULE session state,
        // where none is defined - neither caller-LOCAL nor GLOBAL defaults ever reached the retired
        // functions' nested calls, so the faithful shield is an EMPTY table, not the global one.
        bool swapped = effective is not null;
        if (swapped)
        {
            SessionState.PSVariable.Set("PSDefaultParameterValues", new System.Management.Automation.DefaultParameterDictionary());
        }
        try
        {
            ScriptBlock script = ScriptBlock.Create(scriptText);
            Collection<PSObject> raw = InvokeCommand.InvokeScript(false, script, null, payload);
            Collection<PSObject> output = new();
            foreach (PSObject item in raw)
            {
                if (item?.BaseObject is WarningRecord warning)
                {
                    WriteWarning(warning.Message);
                }
                else
                {
                    output.Add(item!);
                }
            }
            return output;
        }
        finally
        {
            if (swapped)
            {
                SessionState.PSVariable.Set("PSDefaultParameterValues", effective);
            }
        }
    }

    // PS: ($collection | Where-Object <filterProp> -EQ <value>).<resultProp> - case-insensitive
    // -eq filter over a collection property, then member enumeration (0 -> null, 1 -> scalar).
    private static object? GetWhereValue(object? collection, string filterProperty, string value, string resultProperty)
    {
        List<object?> values = new();
        foreach (object item in EnumerateCollection(collection))
        {
            PSObject wrapped = PSObject.AsPSObject(item);
            object? candidate = wrapped.Properties[filterProperty]?.Value;
            if (LanguagePrimitives.Equals(candidate, value, ignoreCase: true))
            {
                PSPropertyInfo? property = wrapped.Properties[resultProperty];
                if (property is not null)
                {
                    values.Add(property.Value);
                }
            }
        }
        if (values.Count == 0)
        {
            return null;
        }
        if (values.Count == 1)
        {
            return values[0];
        }
        return values.ToArray();
    }

    private static IEnumerable<object> EnumerateCollection(object? value)
    {
        if (value is null)
        {
            yield break;
        }
        object baseObject = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (baseObject is string)
        {
            yield return value;
            yield break;
        }
        if (baseObject is IEnumerable enumerable)
        {
            foreach (object? item in enumerable)
            {
                if (item is not null)
                {
                    yield return item;
                }
            }
            yield break;
        }
        yield return value;
    }

    // PS: ($value -Split 'Value\=')[1] - the substring after the first "Value=", or $null when absent.
    private static string? SplitAfterValue(string? value)
    {
        if (value is null)
        {
            return null;
        }
        string[] parts = value.Split(new[] { "Value=" }, StringSplitOptions.None);
        return parts.Length > 1 ? parts[1] : null;
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

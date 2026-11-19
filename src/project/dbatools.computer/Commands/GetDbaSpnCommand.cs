#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Returns the SQL Server SPNs set for a computer or account in Active Directory. Port of
/// public/Get-DbaSpn.ps1; surface pinned by migration/baselines/Get-DbaSpn.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaSpn")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaSpnCommand : DbaBaseCmdlet
{
    /// <summary>The computer(s) whose SQL SPNs to list.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public string[]? ComputerName { get; set; }

    /// <summary>Account name(s) to list SPNs for directly.</summary>
    [Parameter(Position = 1)]
    public string[]? AccountName { get; set; }

    /// <summary>Credential with rights on the domain.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private bool _defaulted;

    protected override void BeginProcessing()
    {
        // PS: if ($ComputerName.Count -eq 0 -and $AccountName.Count -eq 0) { $ComputerName = @($env:COMPUTERNAME) }
        int computerCount = ComputerName?.Length ?? 0;
        int accountCount = AccountName?.Length ?? 0;
        if (computerCount == 0 && accountCount == 0)
        {
            string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
            ComputerName = string.IsNullOrEmpty(machine) ? Array.Empty<string>() : new[] { machine! };
            _defaulted = true;
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (string computer in ComputerName ?? Array.Empty<string>())
        {
            // PS: if ($computer) { if ($computer.EndsWith('$')) { Process-Account; continue } }
            if (!string.IsNullOrEmpty(computer) && computer.EndsWith("$", StringComparison.Ordinal))
            {
                WriteMessage(MessageLevel.Verbose, $"{computer} is an account name. Processing as account.");
                ProcessAccount(computer);
                continue;
            }

            WriteMessage(MessageLevel.Verbose, $"Getting SQL Server SPN for {computer}");
            // PS: $spns = Test-DbaSpn -ComputerName $computer -Credential $Credential (nested cmdlet).
            Collection<PSObject> spns;
            try
            {
                Hashtable splat = new Hashtable { { "ComputerName", computer }, { "Credential", Credential } };
                spns = NestedCommand.Invoke(this, "Test-DbaSpn", splat);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch
            {
                spns = new Collection<PSObject>();
            }

            WriteMessage(MessageLevel.Verbose, $"Calculated {spns.Count} SQL SPN entries that should exist for {computer}");
            int sqlspns = 0;
            foreach (PSObject spn in spns)
            {
                if (spn is null || !LanguagePrimitives.Equals(spn.Properties["IsSet"]?.Value, true, ignoreCase: false))
                {
                    continue;
                }
                sqlspns++;
                object? instanceServiceAccount = spn.Properties["InstanceServiceAccount"]?.Value;

                // PS: if ($accountName) { if ($accountName -eq $spn.InstanceServiceAccount) { emit } } else { emit }
                if (AccountName is not null && AccountName.Length > 0)
                {
                    // PS array -eq scalar: filters; in the boolean if, true when any element matches.
                    if (ArrayEqualsAny(AccountName, instanceServiceAccount))
                    {
                        WriteObject(BuildSpnObject(computer, instanceServiceAccount, spn.Properties["Port"]?.Value, spn.Properties["RequiredSPN"]?.Value));
                    }
                }
                else
                {
                    WriteObject(BuildSpnObject(computer, instanceServiceAccount, spn.Properties["Port"]?.Value, spn.Properties["RequiredSPN"]?.Value));
                }
            }
            WriteMessage(MessageLevel.Verbose, $"Found {sqlspns} set SQL SPN entries for {computer}");
        }

        // PS: if ($AccountName) { foreach ($account in $AccountName) { Process-Account } }
        // Only fires when AccountName was explicitly supplied (not the ComputerName default path).
        if (!_defaulted && AccountName is not null)
        {
            foreach (string account in AccountName)
            {
                ProcessAccount(account);
            }
        }
    }

    // PS begin Process-Account: AD lookup then emit one object per servicePrincipalName.
    private void ProcessAccount(string account)
    {
        WriteMessage(MessageLevel.Verbose, $"Looking for account {account}...");
        string searchFor = account.EndsWith("$", StringComparison.Ordinal) ? "Computer" : "User";

        Collection<PSObject> adResult;
        try
        {
            Hashtable splat = new Hashtable
            {
                { "ADObject", account },
                { "Type", searchFor },
                { "Credential", Credential },
                { "EnableException", true }
            };
            NestedCommand.RequireDbatoolsScriptModule(this);
            adResult = InvokeModuleScoped(
                "param($__p) " +
                "$__module = Get-Module dbatools | Where-Object ModuleType -eq \"Script\" | Select-Object -First 1; " +
                "& $__module { param($p) Get-DbaADObject -ADObject $p.ADObject -Type $p.Type -Credential $p.Credential -EnableException } $__p 3>&1",
                splat);
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch
        {
            WriteMessage(MessageLevel.Warning, $"AD lookup failure. This may be because the domain cannot be resolved for the SQL Server service account ({account}).");
            return;
        }

        // PS: if ($result.Count -gt 0) - a not-found lookup EMITS an explicit $null, which PS
        // collapses to scalar null (Count 0); shape before counting or the null counts as one.
        object? adShaped = ShapeForScript(adResult);
        if (PsCount(adShaped) == 0)
        {
            WriteMessage(MessageLevel.Warning, $"The SQL Service account ({account}) has not been found");
            return;
        }

        object? spnsValue;
        try
        {
            // PS: $results = $result.GetUnderlyingObject(); $spns = $results.Properties.servicePrincipalName
            Collection<PSObject> spnResults = InvokeCommand.InvokeScript(
                false,
                ScriptBlock.Create("param($__r) $__u = $__r.GetUnderlyingObject(); $__u.Properties.servicePrincipalName"),
                null,
                adShaped);
            spnsValue = spnResults.Count == 0 ? null : (spnResults.Count == 1 ? (object?)spnResults[0] : ToArray(spnResults));
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch
        {
            WriteMessage(MessageLevel.Warning, $"The SQL Service account ({account}) has been found, but you don't have enough permission to inspect its SPNs");
            return;
        }

        foreach (object spn in EnumeratePipeline(spnsValue))
        {
            string spnText = LanguagePrimitives.ConvertTo<string>(spn) ?? string.Empty;
            object? port = null;
            // PS: if ($spn -match "\:") { try { $port = [int]($spn -Split "\:")[1] } catch { $port = $null } }
            if (spnText.IndexOf(":", StringComparison.Ordinal) >= 0)
            {
                string[] segments = spnText.Split(':');
                if (segments.Length > 1 && int.TryParse(segments[1], out int p))
                {
                    port = p;
                }
            }
            WriteObject(BuildSpnObject(account, account, port, spnText));
        }
    }

    private static PSObject BuildSpnObject(object? input, object? accountName, object? port, object? spn)
    {
        PSObject obj = new();
        obj.Properties.Add(new PSNoteProperty("Input", input));
        obj.Properties.Add(new PSNoteProperty("AccountName", accountName));
        obj.Properties.Add(new PSNoteProperty("ServiceClass", "MSSQLSvc"));
        obj.Properties.Add(new PSNoteProperty("Port", port));
        obj.Properties.Add(new PSNoteProperty("SPN", spn));
        return obj;
    }


    // PS .Count on a pipeline-shaped value: null (a not-found lookup EMITS an explicit $null,
    // which PS collapses to a scalar null whose Count is 0) -> 0, array -> length, scalar -> 1.
    private static int PsCount(object? value)
    {
        if (value is null)
        {
            return 0;
        }
        object unwrapped = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (unwrapped is object?[] many)
        {
            return many.Length;
        }
        return 1;
    }

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
            Collection<PSObject> raw = InvokeCommand.InvokeScript(false, ScriptBlock.Create(scriptText), null, payload);
            Collection<PSObject> output = new();
            foreach (PSObject item in raw)
            {
                if (item?.BaseObject is WarningRecord warning) { WriteWarning(warning.Message); }
                else { output.Add(item!); }
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

    private static bool ArrayEqualsAny(string[] values, object? candidate)
    {
        foreach (string v in values)
        {
            if (LanguagePrimitives.Equals(v, candidate, ignoreCase: true))
            {
                return true;
            }
        }
        return false;
    }

    private static object? ShapeForScript(Collection<PSObject> items)
    {
        if (items.Count == 0) { return null; }
        if (items.Count == 1) { return items[0]; }
        return ToArray(items);
    }

    private static object[] ToArray(Collection<PSObject> items)
    {
        List<object> list = new();
        foreach (PSObject i in items) { list.Add(i); }
        return list.ToArray();
    }

    private static IEnumerable<object> EnumeratePipeline(object? value)
    {
        if (value is null) { yield break; }
        object baseObject = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (baseObject is string) { yield return value; yield break; }
        if (baseObject is IEnumerable enumerable)
        {
            foreach (object? item in enumerable) { if (item is not null) { yield return item; } }
            yield break;
        }
        yield return value;
    }
}

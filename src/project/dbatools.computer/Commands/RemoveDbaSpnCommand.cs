#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes an SPN (and its constrained-delegation entry) from a service account in Active
/// Directory. Port of public/Remove-DbaSpn.ps1; surface pinned by
/// migration/baselines/Remove-DbaSpn.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaSpn", SupportsShouldProcess = true, DefaultParameterSetName = "Default")]
public sealed class RemoveDbaSpnCommand : DbaBaseCmdlet
{
    /// <summary>The Service Principal Name to remove from Active Directory.</summary>
    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, Position = 0)]
    [Alias("RequiredSPN")]
    [PsStringCast]
    public string? SPN { get; set; }

    /// <summary>The Active Directory account the SPN is registered to.</summary>
    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, Position = 1)]
    [Alias("InstanceServiceAccount", "AccountName")]
    [PsStringCast]
    public string? ServiceAccount { get; set; }

    /// <summary>The credential to use to connect to Active Directory to make the changes.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 2)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS: $Result, $adentry and $spnadobject are FUNCTION-scope, so a throwing statement leaves
    // the value from a PREVIOUS pipeline record in place for the current one (quirk preserved -
    // same family as Test-DbaSpn's $result). _lookupResult holds the pipeline-SHAPED value like
    // the PS variable (a not-found lookup emits an explicit $null, which PS collapses to scalar
    // null with Count 0); _spnAdObject holds the SHAPED VALUES of the servicePrincipalName
    // property for the -contains/-notcontains checks.
    private object? _lookupResult;
    private object? _adEntry;
    private object? _spnAdObject;

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        string serviceAccount = ServiceAccount ?? string.Empty;
        string spn = SPN ?? string.Empty;

        // PS: Write-Message "Looking for account $ServiceAccount..." -Level Verbose
        WriteMessage(MessageLevel.Verbose, $"Looking for account {serviceAccount}...");

        // PS: $searchfor = 'User'; if ($ServiceAccount.EndsWith('$')) { $searchfor = 'Computer' }
        string searchfor = serviceAccount.EndsWith("$", StringComparison.Ordinal) ? "Computer" : "User";

        try
        {
            Hashtable adPayload = new Hashtable
            {
                { "ADObject", serviceAccount },
                { "Type", searchfor },
                { "Credential", Credential }
            };
            NestedCommand.RequireDbatoolsScriptModule(this);
            _lookupResult = ShapeOutput(InvokeModuleScoped(
                "param($__p) " +
                "$__module = Get-Module dbatools | Where-Object ModuleType -eq \"Script\" | Select-Object -First 1; " +
                "& $__module { param($p) Get-DbaADObject -ADObject $p.ADObject -Type $p.Type -Credential $p.Credential -EnableException } $__p 3>&1",
                adPayload));
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (RuntimeException rex)
        {
            // PS: Stop-Function WITHOUT return - non-EnableException mode warns and FALLS THROUGH.
            string inner = rex.ErrorRecord?.Exception?.Message ?? rex.Message;
            StopFunction($"AD lookup failure. This may be because the domain cannot be resolved for the SQL Server service account ({serviceAccount}). {inner}", target: serviceAccount, errorRecord: rex.ErrorRecord, continueLoop: true);
        }
        catch (Exception ex)
        {
            StopFunction($"AD lookup failure. This may be because the domain cannot be resolved for the SQL Server service account ({serviceAccount}). {ex.Message}", target: serviceAccount, exception: ex, continueLoop: true);
        }

        if (PsCount(_lookupResult) > 0)
        {
            try
            {
                // PS: $adentry = $Result.GetUnderlyingObject()
                // Wrapped so a multi-result (array-shaped) lookup binds as ONE $__r argument
                // instead of being unpacked by the params-array binding.
                Collection<PSObject> fetched = InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__r) $__r.GetUnderlyingObject()"), null, new object?[] { _lookupResult });
                _adEntry = ShapeOutput(fetched);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException rex)
            {
                string inner = rex.ErrorRecord?.Exception?.Message ?? rex.Message;
                StopFunction($"The SQL Service account ({serviceAccount}) has been found, but you don't have enough permission to inspect its properties {inner}", target: serviceAccount, errorRecord: rex.ErrorRecord, continueLoop: true);
            }
        }
        else
        {
            StopFunction($"The SQL Service account ({serviceAccount}) has not been found", target: serviceAccount, continueLoop: true);
        }

        // PS: $delegate = $true
        bool delegate_ = true;

        // PS: $spnadobject = $adentry.Properties['servicePrincipalName'] - a top-level statement,
        // so its failure (index into a null $adentry.Properties after a failed lookup) surfaces as
        // a non-terminating error and execution continues with the next statement, keeping the
        // previous record's value. The VALUES enumerate through the nested pipeline; they feed the
        // -contains/-notcontains checks (identical element comparison), while the removal itself
        // re-chains off the entry's live property cache below.
        try
        {
            Collection<PSObject> fetched = InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__e) $__e.Properties['servicePrincipalName']"), null, _adEntry);
            _spnAdObject = ShapeOutput(fetched);
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (RuntimeException rex)
        {
            WriteError(rex.ErrorRecord ?? new ErrorRecord(rex, "InvokeMethodOnNull", ErrorCategory.InvalidOperation, _adEntry));
        }

        bool set = false;
        string status = string.Empty;

        // PS: if ($spnadobject -notcontains $spn) { warning + status }
        if (!PsContains(_spnAdObject, spn))
        {
            WriteMessage(MessageLevel.Warning, $"SPN {spn} not found");
            status = "SPN not found";
            set = false;
        }

        if (ShouldProcess(spn, "Removing SPN for service account"))
        {
            try
            {
                // PS: if ($spnadobject -contains $spn) { $null = $spnadobject.Remove($spn);
                //     $adentry.CommitChanges(); ... }
                if (PsContains(_spnAdObject, spn))
                {
                    // PS: $null = $spnadobject.Remove($spn); $adentry.CommitChanges() - the cached
                    // $spnadobject IS the entry's live property cache, so re-chaining off the entry
                    // removes from the same collection (a round-tripped copy would be a fixed-size
                    // snapshot whose Remove throws).
                    InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__e, $__spn) $null = $__e.Properties['servicePrincipalName'].Remove($__spn); $__e.CommitChanges()"), null, _adEntry, spn);
                    WriteMessage(MessageLevel.Verbose, $"Remove SPN {spn} for {serviceAccount}");
                    set = false;
                    status = "Successfully removed SPN";
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException rex)
            {
                // PS: Write-Message ... -Target $ServiceAccountWrite - an UNDEFINED variable, so
                // the target is null (typo preserved).
                string inner = rex.ErrorRecord?.Exception?.Message ?? rex.Message;
                WriteMessage(MessageLevel.Warning, $"Could not remove SPN. {inner}", target: null, exception: rex.ErrorRecord?.Exception ?? rex);
                set = true;
                status = "Failed to remove SPN";
                delegate_ = false;
            }

            WriteObject(BuildResultObject(spn, serviceAccount, "servicePrincipalName", set, status));
        }

        // PS: the delegation ShouldProcess wraps the whole cleanup, including the not-found shape.
        if (ShouldProcess(spn, "Removing delegation for service account for SPN"))
        {
            if (delegate_)
            {
                // PS: if ($adentry.Properties['msDS-AllowedToDelegateTo'] -notcontains $spn) - the
                // fetch is part of the if statement, so its failure kills the WHOLE if (neither
                // branch runs, nothing is emitted) as a non-terminating error.
                Collection<PSObject> delegationValues;
                try
                {
                    delegationValues = InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__e) $__e.Properties['msDS-AllowedToDelegateTo']"), null, _adEntry);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException rex)
                {
                    WriteError(rex.ErrorRecord ?? new ErrorRecord(rex, "InvokeMethodOnNull", ErrorCategory.InvalidOperation, _adEntry));
                    return;
                }

                if (!PsContains(ShapeOutput(delegationValues), spn))
                {
                    WriteObject(BuildResultObject(spn, serviceAccount, "msDS-AllowedToDelegateTo", false, "Delegation not found"));
                }
                else
                {
                    try
                    {
                        // PS: $null = $adentry.Properties['msDS-AllowedToDelegateTo'].Remove($spn);
                        //     $adentry.CommitChanges() - chained fresh off $adentry.
                        InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__e, $__spn) $null = $__e.Properties['msDS-AllowedToDelegateTo'].Remove($__spn); $__e.CommitChanges()"), null, _adEntry, spn);
                        WriteMessage(MessageLevel.Verbose, $"Removed kerberos delegation {spn} for {serviceAccount}");
                        set = false;
                        status = "Successfully removed delegation";
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (RuntimeException rex)
                    {
                        string inner = rex.ErrorRecord?.Exception?.Message ?? rex.Message;
                        WriteMessage(MessageLevel.Warning, $"Could not remove delegation. {inner}", target: serviceAccount, exception: rex.ErrorRecord?.Exception ?? rex);
                        set = true;
                        status = "Failed to remove delegation";
                    }

                    WriteObject(BuildResultObject(spn, serviceAccount, "msDS-AllowedToDelegateTo", set, status));
                }
            }
        }
    }

    // PS: [PSCustomObject]@{ Name; ServiceAccount; Property; IsSet; Notes } - fixed order, no
    // display set (a parameterless PSObject carries the PSCustomObject type names).
    private static PSObject BuildResultObject(string spn, string serviceAccount, string property, bool isSet, string notes)
    {
        PSObject obj = new();
        obj.Properties.Add(new PSNoteProperty("Name", spn));
        obj.Properties.Add(new PSNoteProperty("ServiceAccount", serviceAccount));
        obj.Properties.Add(new PSNoteProperty("Property", property));
        obj.Properties.Add(new PSNoteProperty("IsSet", isSet));
        obj.Properties.Add(new PSNoteProperty("Notes", notes));
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

    // PS -contains: enumerates a collection LHS (or treats a scalar as one element; a null LHS
    // contains nothing) and compares each element with -eq semantics (engine equality,
    // case-insensitive for strings).
    private static bool PsContains(object? collection, object? value)
    {
        if (collection is null)
        {
            return false;
        }
        object unwrapped = collection is PSObject wrapped ? wrapped.BaseObject : collection;
        if (unwrapped is string)
        {
            return LanguagePrimitives.Equals(unwrapped, value, ignoreCase: true);
        }
        if (unwrapped is IEnumerable enumerable)
        {
            foreach (object? item in enumerable)
            {
                if (LanguagePrimitives.Equals(item, value, ignoreCase: true))
                {
                    return true;
                }
            }
            return false;
        }
        return LanguagePrimitives.Equals(unwrapped, value, ignoreCase: true);
    }

    // The module-scoped private-helper invocation: shield $PSDefaultParameterValues with an empty
    // table for the duration of the nested window (the PSDPV shield) and re-emit 3>&1-merged
    // WarningRecords through the outer cmdlet.
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

    // PS pipeline-assignment shape: empty -> null, one -> the scalar, many -> object[].
    private static object? ShapeOutput(Collection<PSObject> output)
    {
        if (output.Count == 0)
        {
            return null;
        }
        if (output.Count == 1)
        {
            return output[0];
        }
        object?[] many = new object?[output.Count];
        for (int i = 0; i < output.Count; i++)
        {
            many[i] = output[i];
        }
        return many;
    }
}

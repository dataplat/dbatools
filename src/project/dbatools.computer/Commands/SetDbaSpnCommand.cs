#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Adds an SPN (and by default constrained delegation to the same SPN) to a service account in
/// Active Directory. Port of public/Set-DbaSpn.ps1; surface pinned by
/// migration/baselines/Set-DbaSpn.json.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaSpn", SupportsShouldProcess = true, DefaultParameterSetName = "Default")]
public sealed class SetDbaSpnCommand : DbaBaseCmdlet
{
    /// <summary>The Service Principal Name to register in Active Directory.</summary>
    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, Position = 0)]
    [Alias("RequiredSPN")]
    [PsStringCast]
    public string? SPN { get; set; }

    /// <summary>The Active Directory account that runs the SQL Server service and will own the SPN.</summary>
    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, Position = 1)]
    [Alias("InstanceServiceAccount", "AccountName")]
    [PsStringCast]
    public string? ServiceAccount { get; set; }

    /// <summary>The credential to use to connect to Active Directory to make the changes.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 2)]
    public PSCredential? Credential { get; set; }

    /// <summary>Prevents automatic configuration of constrained delegation for the SPN.</summary>
    [Parameter]
    public SwitchParameter NoDelegation { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS: $Result and $adentry are FUNCTION-scope. Keep the pipeline-shaped lookup value because
    // the throwing-lookup path has not been behaviorally characterized. Clear the DirectoryEntry
    // per record: reusing it after a later lookup cannot resolve an account would apply that
    // record's SPN to an earlier account.
    private object? _lookupResult;
    private object? _adEntry;

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        _adEntry = null;

        string serviceAccount = ServiceAccount ?? string.Empty;
        string spn = SPN ?? string.Empty;

        // PS: Write-Message "Looking for account $ServiceAccount..." -Level Verbose
        WriteMessage(MessageLevel.Verbose, $"Looking for account {serviceAccount}...");

        // PS: $searchfor = 'User'; if ($ServiceAccount.EndsWith('$')) { $searchfor = 'Computer' }
        // (the char overload of EndsWith is ordinal).
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
            // PS: Stop-Function "AD lookup failure. ... ($ServiceAccount). $($_.Exception.Message)"
            // WITHOUT return - non-EnableException mode warns and FALLS THROUGH to the next
            // statement (continueLoop keeps Interrupted unset; there is deliberately no
            // C# continue here).
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
                // PS: $adentry = $Result.GetUnderlyingObject() - the method resolves on the
                // pipeline-shaped value (scalar for one result; a multi-result array has no such
                // method and fails the statement exactly like PS).
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

        // PS: $delegate = $true BEFORE ShouldProcess, so under -WhatIf both prompts render.
        bool delegate_ = true;
        if (ShouldProcess(spn, "Adding SPN to service account"))
        {
            bool set;
            string status;
            try
            {
                // PS: $null = $adentry.Properties['serviceprincipalname'].Add($spn);
                //     $status = "Successfully added SPN"; $adentry.CommitChanges()
                // A failure in Add OR CommitChanges lands in the same catch.
                InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__e, $__spn) $null = $__e.Properties['serviceprincipalname'].Add($__spn); $__e.CommitChanges()"), null, _adEntry, spn);
                status = "Successfully added SPN";
                WriteMessage(MessageLevel.Verbose, $"Added SPN {spn} to {serviceAccount}");
                set = true;
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException rex)
            {
                // PS: Write-Message -Level Warning -EnableException $EnableException.ToBool()
                //     -ErrorRecord $_ - warns (and under EnableException also writes the error
                //     record) but NEVER throws; flow continues to the output object.
                string inner = rex.ErrorRecord?.Exception?.Message ?? rex.Message;
                WriteMessage(MessageLevel.Warning, $"Could not add SPN. {inner}", target: serviceAccount, exception: rex.ErrorRecord?.Exception ?? rex);
                set = false;
                status = "Failed to add SPN";
                delegate_ = false;
            }

            WriteObject(BuildResultObject(spn, serviceAccount, "servicePrincipalName", set, status));
        }

        // PS: if ($delegate) { if (!$NoDelegation) { ... } else { verbose skip } }
        if (delegate_)
        {
            if (!NoDelegation.ToBool())
            {
                if (ShouldProcess(spn, "Adding constrained delegation to service account for SPN"))
                {
                    bool set;
                    string status;
                    try
                    {
                        InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__e, $__spn) $null = $__e.Properties['msDS-AllowedToDelegateTo'].Add($__spn); $__e.CommitChanges()"), null, _adEntry, spn);
                        WriteMessage(MessageLevel.Verbose, $"Added kerberos delegation to {spn} for {serviceAccount}");
                        set = true;
                        status = "Successfully added constrained delegation";
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (RuntimeException rex)
                    {
                        string inner = rex.ErrorRecord?.Exception?.Message ?? rex.Message;
                        WriteMessage(MessageLevel.Warning, $"Could not add delegation. {inner}", target: serviceAccount, exception: rex.ErrorRecord?.Exception ?? rex);
                        set = false;
                        status = "Failed to add constrained delegation";
                    }

                    WriteObject(BuildResultObject(spn, serviceAccount, "msDS-AllowedToDelegateTo", set, status));
                }
            }
            else
            {
                WriteMessage(MessageLevel.Verbose, "Skipping delegation as instructed");
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

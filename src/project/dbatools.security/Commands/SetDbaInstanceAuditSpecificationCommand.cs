#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Alters existing SERVER AUDIT SPECIFICATION objects. NEW designed command - no PS ancestor, pure C#,
/// no hop. Surface pinned by migration/designed/Set-DbaInstanceAuditSpecification.json (signed 2026-07-22).
///
/// SCOPE. dbatools has Get-DbaInstanceAuditSpecification and Copy-DbaInstanceAuditSpecification and this
/// campaign added New-DbaInstanceAuditSpecification; this fills the ALTER gap. Re-points a specification at
/// a different parent audit, adds or removes audit action types, and enables or disables it. Server-level
/// only; database-level audit specifications are out of this batch.
///
/// THE STATE=OFF SEQUENCE IS THE CMDLET'S JOB, NOT SMO'S - the signature gotcha of this row, identical to
/// Set-DbaInstanceAudit. In AuditSpecification.cs ScriptAlter emits no STATE clause and, on an EXISTING
/// spec, AddAuditSpecificationDetail/RemoveAuditSpecificationDetail each run their own immediate
/// ALTER ... ADD/DROP round-trip - none of them disable first, yet ALTER SERVER AUDIT SPECIFICATION and its
/// detail mutations require STATE=OFF. So this cmdlet captures Enabled, Disable()s an enabled spec before
/// mutating, applies the AuditName re-point and the detail removes-then-adds, then restores the state - and
/// restores the ORIGINAL state if a mutation throws. This gets its own integration test against an ENABLED
/// specification; a test that only altered a disabled spec would pass while the bug shipped.
///
/// ALTER CHANGES EXACTLY ONE THING - THE PARENT AUDIT. ScriptAlter adds a query ONLY when AuditName is dirty
/// and non-empty; otherwise no statement is emitted at all. So -Audit re-points the specification (its own
/// "Re-pointing" ShouldProcess target) and setting Enabled and calling Alter() does literally nothing - the
/// state is driven by Enable()/Disable() methods (Enabled is access='Read'), not Alter().
///
/// -AddAction AND -RemoveAction ARE SEPARATE, NOT A REPLACING SET. The SMO surface is genuinely
/// additive/subtractive with no set-the-whole-list operation, so a single replacing parameter would have to
/// diff and silently discard actions the caller never named. Removes are applied BEFORE adds so an action
/// can be moved between specs in one invocation without a transient duplicate. Both take the SMO enum array
/// directly so the accepted values can never drift from SMO and PowerShell tab-completes them. Server-level
/// details carry only the action type, so there is no object/principal scoping.
///
/// NO -NewName. Name is [SfcKey] ReadOnlyAfterCreation on an audit specification, so it cannot be renamed
/// through SMO - a deliberate asymmetry with Set-DbaInstanceAudit, whose Audit.Name is renameable.
///
/// ENABLE AND DISABLE ARE TWO SWITCHES, NOT ONE (Enabled is access='Read'), mutually exclusive
/// (StopFunction when both bound). When NEITHER is bound the spec's state is preserved across the
/// Disable/mutate/Enable sequence.
///
/// DUALITY. Either -SqlInstance or -InputObject, no parameter sets (new-commands.md 1.2). -AuditSpecification
/// is REQUIRED on the -SqlInstance feeder (matching the sibling Set-DbaInstanceAudit's -Audit requirement);
/// it stays mandatory:false on the surface and is enforced at runtime so the signed spec is not violated.
/// -InputObject is Smo.ServerAuditSpecification[], the type Get-DbaInstanceAuditSpecification emits.
///
/// OUTPUT. Re-emits the refreshed Smo.ServerAuditSpecification decorated exactly like
/// Get-DbaInstanceAuditSpecification (ComputerName/InstanceName/SqlInstance and the un-aliased default view)
/// so Get -> Set -> Get composes. Replace-then-add. CONFIRMIMPACT Medium because satisfying the STATE=OFF
/// rule transiently stops the specification from auditing - a compliance-relevant side effect.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaInstanceAuditSpecification", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.ServerAuditSpecification))]
public sealed class SetDbaInstanceAuditSpecificationCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The name(s) of the audit specification(s) to alter. Required when -SqlInstance is used.</summary>
    [Parameter(Position = 2)]
    public string[]? AuditSpecification { get; set; }

    /// <summary>Re-points the specification to a different parent server audit.</summary>
    [Parameter(Position = 3)]
    public string? Audit { get; set; }

    /// <summary>Audit action type(s) to ADD to the specification.</summary>
    [Parameter(Position = 4)]
    public AuditActionType[]? AddAction { get; set; }

    /// <summary>Audit action type(s) to REMOVE from the specification. Applied before adds.</summary>
    [Parameter(Position = 5)]
    public AuditActionType[]? RemoveAction { get; set; }

    /// <summary>SMO ServerAuditSpecification object(s) from Get-DbaInstanceAuditSpecification.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public ServerAuditSpecification[]? InputObject { get; set; }

    /// <summary>Enable the specification. Mutually exclusive with -Disable.</summary>
    [Parameter]
    public SwitchParameter Enable { get; set; }

    /// <summary>Disable the specification. Mutually exclusive with -Enable.</summary>
    [Parameter]
    public SwitchParameter Disable { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Duality, no parameter sets (new-commands.md 1.2). Checked here, not in BeginProcessing, because a
        // pipeline-bound InputObject is not in BoundParameters until ProcessRecord.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        // -Enable and -Disable are mutually exclusive (two switches carry the tri-state).
        if (TestBound(nameof(Enable)) && TestBound(nameof(Disable)))
        {
            StopFunction("You cannot specify both -Enable and -Disable");
            return;
        }

        if (TestBound(nameof(SqlInstance)))
        {
            if (AuditSpecification is null || AuditSpecification.Length == 0)
            {
                StopFunction("AuditSpecification is required when SqlInstance is specified");
                return;
            }

            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                Server? server = ConnectInstance(instance, "Failure", minimumVersion: 10);
                if (server is null)
                {
                    continue;
                }

                foreach (ServerAuditSpecification specObj in ResolveSpecifications(server))
                {
                    ProcessSpecification(specObj);
                }
            }
        }

        // Feeder 2: ServerAuditSpecification objects piped from Get-DbaInstanceAuditSpecification. The parent
        // server is resolved PER RECORD (spec.Parent = Server) - never carried across records.
        foreach (ServerAuditSpecification specObj in InputObject ?? Array.Empty<ServerAuditSpecification>())
        {
            ProcessSpecification(specObj);
        }
    }

    // One worker, two feeders (new-commands.md 1.2).
    private void ProcessSpecification(ServerAuditSpecification specObj)
    {
        Server? server = specObj.Parent;
        if (server is null)
        {
            StopFunction(String.Format("Server audit specification {0} has no parent server", specObj.Name),
                target: specObj, category: ErrorCategory.InvalidData, continueLoop: true);
            return;
        }

        string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);

        // Version guard - enforced here for the InputObject feeder too, which never passes through the
        // minimumVersion connect. Audit specifications require SQL Server 2008 (10.0).
        if (server.VersionMajor < 10)
        {
            StopFunction(String.Format("Altering a server audit specification requires SQL Server 2008 (10.0) or later; {0} is version {1}", target, server.VersionMajor),
                target: specObj, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        bool wantRepoint = TestBound(nameof(Audit));
        bool wantDetails = TestBound(nameof(AddAction)) || TestBound(nameof(RemoveAction));
        bool wantState = TestBound(nameof(Enable)) || TestBound(nameof(Disable));

        // Two ShouldProcess targets, verbatim from the signed spec's shouldProcessTargets: the "Altering"
        // umbrella covers detail add/remove and state; the "Re-pointing" target covers -Audit. Under -WhatIf
        // both strings print and nothing mutates.
        bool alterApproved = false;
        if (wantDetails || wantState)
        {
            string alterAction = String.Format("Altering server audit specification {0}", specObj.Name);
            alterApproved = ShouldProcess(target, alterAction);
        }

        bool repointApproved = false;
        if (wantRepoint)
        {
            string repointAction = String.Format("Re-pointing server audit specification {0} to audit {1}", specObj.Name, Audit);
            repointApproved = ShouldProcess(target, repointAction);
        }

        if (alterApproved || repointApproved)
        {
            bool originalEnabled = specObj.Enabled;
            bool desiredEnabled = originalEnabled;
            if (alterApproved && TestBound(nameof(Enable)))
            {
                desiredEnabled = true;
            }
            else if (alterApproved && TestBound(nameof(Disable)))
            {
                desiredEnabled = false;
            }

            // A re-point or a detail change mutates DDL that requires STATE=OFF; a bare state toggle does not.
            bool needsStateOff = repointApproved || (alterApproved && wantDetails);

            try
            {
                if (needsStateOff && specObj.Enabled)
                {
                    specObj.Disable();
                }

                if (repointApproved)
                {
                    // Alter changes exactly one thing - the parent audit - and only when AuditName is dirty.
                    specObj.AuditName = Audit;
                    specObj.Alter();
                }

                if (alterApproved && wantDetails)
                {
                    // Removes before adds so an action can be moved between specs without a transient duplicate.
                    foreach (AuditActionType actionType in RemoveAction ?? Array.Empty<AuditActionType>())
                    {
                        specObj.RemoveAuditSpecificationDetail(new AuditSpecificationDetail(actionType));
                    }
                    foreach (AuditActionType actionType in AddAction ?? Array.Empty<AuditActionType>())
                    {
                        specObj.AddAuditSpecificationDetail(new AuditSpecificationDetail(actionType));
                    }
                }

                // Restore/apply the desired state. When neither -Enable nor -Disable was bound this re-enables
                // a spec the mutation transiently disabled (state preserved).
                if (desiredEnabled && !specObj.Enabled)
                {
                    specObj.Enable();
                }
                else if (!desiredEnabled && specObj.Enabled)
                {
                    specObj.Disable();
                }
            }
            catch (Exception ex)
            {
                // Restore the original running state so a failed mutation does not leave auditing off.
                try
                {
                    if (originalEnabled && !specObj.Enabled)
                    {
                        specObj.Enable();
                    }
                }
                catch (Exception)
                {
                    // Best-effort restore; the primary failure is reported below.
                }

                StopFunction(String.Format("Failure altering server audit specification {0} on {1}", specObj.Name, target),
                    target: specObj,
                    errorRecord: new ErrorRecord(ex, "dbatools_SetDbaInstanceAuditSpecification", ErrorCategory.InvalidOperation, specObj),
                    continueLoop: true);
                return;
            }
        }

        try
        {
            specObj.Refresh();
        }
        catch (Exception)
        {
            // A refresh failure must not lose the object the caller just successfully altered.
        }

        WriteSpecification(specObj, server);
    }

    // Not a lazy iterator ON PURPOSE: a requested-but-missing specification must be REPORTED (warn + continue,
    // terminating under -EnableException), never silently skipped.
    private List<ServerAuditSpecification> ResolveSpecifications(Server server)
    {
        List<ServerAuditSpecification> resolved = new();

        foreach (string specName in AuditSpecification ?? Array.Empty<string>())
        {
            ServerAuditSpecification? specObj = server.ServerAuditSpecifications[specName];
            if (specObj is null)
            {
                StopFunction(String.Format("Server audit specification {0} does not exist on {1}", specName, server.Name),
                    target: specName, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            resolved.Add(specObj);
        }

        return resolved;
    }

    // Decorated exactly like Get-DbaInstanceAuditSpecification: the instance triple plus the un-aliased
    // default view. Replace-then-add so a re-emitted object (piped in from the getCounterpart) never throws
    // on a duplicate member.
    private void WriteSpecification(ServerAuditSpecification specObj, Server server)
    {
        PSObject wrapped = PSObject.AsPSObject(specObj);
        ReplaceNoteProperty(wrapped, "ComputerName", Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server));
        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server));

        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
            "ComputerName", "InstanceName", "SqlInstance", "ID", "Name", "AuditName", "Enabled",
            "CreateDate", "DateLastModified", "Guid");
        WriteObject(wrapped);
    }

    private static void ReplaceNoteProperty(PSObject wrapped, string name, object? value)
    {
        if (wrapped.Properties[name] is not null)
        {
            wrapped.Properties.Remove(name);
        }
        wrapped.Properties.Add(new PSNoteProperty(name, value));
    }
}

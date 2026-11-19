#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Drops SERVER AUDIT SPECIFICATION objects. NEW designed command - no PS ancestor, pure C#, no hop.
/// Surface pinned by migration/designed/Remove-DbaInstanceAuditSpecification.json (signed 2026-07-21).
///
/// SCOPE. dbatools has Get-DbaInstanceAuditSpecification and Copy-DbaInstanceAuditSpecification and this
/// campaign added New-/Set-DbaInstanceAuditSpecification; this fills the DROP gap. Server-level only;
/// database-level audit specifications are out of this batch.
///
/// DISABLE BEFORE DROP. DROP SERVER AUDIT SPECIFICATION requires STATE=OFF, so an ENABLED specification is
/// Disable()d first (the separate EnableDisable path, not Alter) - the established dbatools precedent at
/// Copy-DbaInstanceAudit.ps1:185-187. This is the distinguishing leg: dropping an enabled spec succeeds
/// only because the cmdlet sequences the Disable(); a test that only drops a disabled spec would pass while
/// the bug shipped.
///
/// NO -Force PARAMETER, DELIBERATELY - the asymmetry with Remove-DbaInstanceAudit. An audit specification
/// is a LEAF: nothing depends on it, so there is no dependent-object situation for -Force to resolve.
/// Remove-DbaInstanceAudit needs -Force precisely because audits DO have dependent specifications and SMO's
/// ScriptDrop does not cascade despite its doc comment. Adding a no-op -Force here would imply a hazard that
/// does not exist.
///
/// DUALITY. Either -SqlInstance or -InputObject, no parameter sets (new-commands.md 1.2).
/// -AuditSpecification is REQUIRED on the -SqlInstance feeder; it stays mandatory:false on the surface and
/// is enforced at runtime so the signed spec is not violated. -InputObject is
/// Smo.ServerAuditSpecification[], the type Get-DbaInstanceAuditSpecification emits.
///
/// OUTPUT. Declares [OutputType(Smo.ServerAuditSpecification)] and emits the pre-drop snapshot of what it
/// removed, decorated exactly like Get-DbaInstanceAuditSpecification (the instance triple and the un-aliased
/// default view) so a caller can log what was dropped. The instance-triple decoration values are captured
/// BEFORE the drop; the emitted object's .State reflects a dropped object, as the signed spec anticipates.
/// CONFIRMIMPACT High per the section 1.3 Remove- rule.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaInstanceAuditSpecification", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.ServerAuditSpecification))]
public sealed class RemoveDbaInstanceAuditSpecificationCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The name(s) of the audit specification(s) to drop. Required when -SqlInstance is used.</summary>
    [Parameter(Position = 2)]
    public string[]? AuditSpecification { get; set; }

    /// <summary>SMO ServerAuditSpecification object(s) from Get-DbaInstanceAuditSpecification.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public ServerAuditSpecification[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Specs to drop are BUFFERED here and dropped in EndProcessing, never in ProcessRecord. The
    // getCounterpart Get-DbaInstanceAuditSpecification streams its results straight off the live
    // server.ServerAuditSpecifications collection, so dropping a spec mid-pipeline (Get- | Remove-) would
    // mutate the collection Get- is still enumerating and throw "Collection was modified after the
    // enumerator was instantiated". Deferring every Drop() to EndProcessing lets Get- fully drain first.
    private readonly List<ServerAuditSpecification> _pending = new();

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

                // ResolveSpecifications reports missing names now (warn + continue); the resolved objects
                // are buffered and dropped in EndProcessing.
                _pending.AddRange(ResolveSpecifications(server));
            }
        }

        // Feeder 2: ServerAuditSpecification objects piped from Get-DbaInstanceAuditSpecification. The parent
        // server is resolved PER RECORD (spec.Parent = Server) - never carried across records.
        foreach (ServerAuditSpecification specObj in InputObject ?? Array.Empty<ServerAuditSpecification>())
        {
            _pending.Add(specObj);
        }
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        // Every Drop() happens here, after the upstream getCounterpart has finished streaming - see the
        // _pending field comment.
        foreach (ServerAuditSpecification specObj in _pending)
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

        if (server.VersionMajor < 10)
        {
            StopFunction(String.Format("Server audit specifications require SQL Server 2008 (10.0) or later; {0} is version {1}", target, server.VersionMajor),
                target: specObj, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        // ShouldProcess string is VERBATIM from the signed spec's shouldProcessTargets.
        string action = String.Format("Removing server audit specification {0}", specObj.Name);
        if (!ShouldProcess(target, action))
        {
            return;
        }

        // Capture the instance-triple decoration values BEFORE the drop - the values come from the server
        // and are safe to read regardless of the object's post-drop state.
        string computerName = Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server);
        string instanceName = server.ServiceName;
        string sqlInstance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);

        try
        {
            // DROP SERVER AUDIT SPECIFICATION requires STATE=OFF - disable an enabled spec first.
            if (specObj.Enabled)
            {
                specObj.Disable();
            }

            specObj.Drop();
        }
        catch (Exception ex)
        {
            StopFunction(String.Format("Failure dropping server audit specification {0} on {1}", specObj.Name, target),
                target: specObj,
                errorRecord: new ErrorRecord(ex, "dbatools_RemoveDbaInstanceAuditSpecification", ErrorCategory.InvalidOperation, specObj),
                continueLoop: true);
            return;
        }

        WriteSpecification(specObj, computerName, instanceName, sqlInstance);
    }

    // Not a lazy iterator ON PURPOSE: a requested-but-missing specification must be REPORTED (warn +
    // continue, terminating under -EnableException), never silently skipped.
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
    // default view. Replace-then-add so a re-emitted object (piped in from the getCounterpart, already
    // decorated) never throws on a duplicate member.
    private void WriteSpecification(ServerAuditSpecification specObj, string computerName, string instanceName, string sqlInstance)
    {
        PSObject wrapped = PSObject.AsPSObject(specObj);
        ReplaceNoteProperty(wrapped, "ComputerName", computerName);
        ReplaceNoteProperty(wrapped, "InstanceName", instanceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", sqlInstance);

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

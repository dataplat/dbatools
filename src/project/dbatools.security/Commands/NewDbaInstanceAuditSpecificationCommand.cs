#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates SERVER AUDIT SPECIFICATION objects. NEW designed command - no PS ancestor, pure C#,
/// no hop. Surface pinned by migration/designed/New-DbaInstanceAuditSpecification.json (signed).
///
/// SCOPE. dbatools has Get-DbaInstanceAuditSpecification and Copy-DbaInstanceAuditSpecification
/// but no way to CREATE one - verified, no New-/Set-/Remove- exists in either repo. Server-level
/// only; database-level audit specifications are out of this batch.
///
/// SMO. new ServerAuditSpecification(server, name); AuditName names the parent SERVER AUDIT and is
/// required (ScriptCreate throws PropertyNotSetException("AuditName") when unset,
/// AuditSpecification.cs:388-391) - validated via TestBound rather than [Parameter(Mandatory)]
/// because the SqlInstance/InputObject duality forbids marking it mandatory. Details are added
/// BEFORE Create(): on a not-yet-created spec AddAuditSpecificationDetail buffers into
/// AuditSpecificationDetailsList (:231-234) and ScriptCreate flushes them into the single CREATE
/// statement (:412-415) - one round-trip, not one per action. -Enable is a METHOD CALL: Enabled is
/// access='Read' (ServerAuditSpecification.xml:11), so the object is created disabled and Enable()
/// (:534) runs after Create() when -Enable is bound.
///
/// SERVER-LEVEL DETAILS CARRY ONLY THE ACTION. SqlEnum/xml/ServerAuditSpecificationDetail.xml:17-20
/// hardcodes ObjectClass/ObjectSchema/ObjectName/Principal to '' for the server variant, so the
/// surface exposes -AuditActionType only and uses the single-argument
/// AuditSpecificationDetail(AuditActionType) constructor (:657) - the object/principal scoping the
/// four-and-five-argument constructors add would be a filtering capability the server-level object
/// does not have. -AuditActionType is the SMO enum array directly so its accepted values can never
/// drift from the 62 members SMO supports and PowerShell tab-completes them.
///
/// INPUTOBJECT TYPE. -InputObject is Smo.Server[], not the getCounterpart's emitted type: an object
/// that does not exist yet cannot be piped in (house precedent New-DbaLinkedServer). new-commands.md
/// 1.2's "InputObject is the type the Get- emits" rule governs Set-/Remove-, where it already exists.
///
/// DUALITY. No parameter sets. ProcessRecord runs TestBound(SqlInstance, InputObject) and
/// StopFunction("You must supply either -SqlInstance or an Input Object").
///
/// OUTPUT. Re-emits the refreshed Smo.ServerAuditSpecification decorated exactly like
/// Get-DbaInstanceAuditSpecification - ComputerName/InstanceName/SqlInstance NoteProperties and the
/// un-aliased default view - so Get -> New -> Get composes. Replace-then-add. CONFIRMIMPACT Medium.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaInstanceAuditSpecification", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.ServerAuditSpecification))]
public sealed class NewDbaInstanceAuditSpecificationCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The name(s) of the server audit specification(s) to create.</summary>
    [Parameter(Position = 2)]
    public string[]? AuditSpecification { get; set; }

    /// <summary>The parent server audit the specification writes to. Required.</summary>
    [Parameter(Position = 3)]
    public string? Audit { get; set; }

    /// <summary>The server-level audit action group(s) the specification records.</summary>
    [Parameter(Position = 4)]
    public AuditActionType[]? AuditActionType { get; set; }

    /// <summary>SMO Server object(s), typically from Connect-DbaInstance.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public Server[]? InputObject { get; set; }

    /// <summary>Enable the specification immediately after creating it (created disabled by default).</summary>
    [Parameter]
    public SwitchParameter Enable { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Duality, no parameter sets. Checked here, not in BeginProcessing, because a pipeline-bound
        // InputObject is not in BoundParameters until ProcessRecord.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        if (AuditSpecification is null || AuditSpecification.Length == 0)
        {
            StopFunction("You must specify at least one audit specification name via -AuditSpecification");
            return;
        }

        // Parent audit is required at create time; the duality forbids marking it [Parameter(Mandatory)].
        if (String.IsNullOrEmpty(Audit))
        {
            StopFunction("You must specify the parent audit via -Audit when creating an audit specification");
            return;
        }

        if (TestBound(nameof(SqlInstance)))
        {
            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                Server? server = ConnectInstance(instance, "Failure", minimumVersion: 10);
                if (server is null)
                {
                    continue;
                }

                ProcessServer(server);
            }
        }

        // Feeder 2: Server objects piped from Connect-DbaInstance.
        foreach (Server server in InputObject ?? Array.Empty<Server>())
        {
            ProcessServer(server);
        }
    }

    // One worker, two feeders.
    private void ProcessServer(Server server)
    {
        string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);

        foreach (string specName in AuditSpecification!)
        {
            // ShouldProcess string is VERBATIM from the signed spec's shouldProcessTargets.
            string action = String.Format("Creating server audit specification {0} for audit {1}", specName, Audit);
            if (!ShouldProcess(target, action))
            {
                continue;
            }

            ServerAuditSpecification specObj;
            try
            {
                specObj = new ServerAuditSpecification(server, specName);
                specObj.AuditName = Audit;

                // Buffer the action details BEFORE Create() so ScriptCreate flushes them into the
                // single CREATE statement (AuditSpecification.cs:412-415).
                foreach (AuditActionType actionType in AuditActionType ?? Array.Empty<AuditActionType>())
                {
                    specObj.AddAuditSpecificationDetail(new AuditSpecificationDetail(actionType));
                }

                specObj.Create();

                // Enabled is read-only; -Enable is a method call, not a property set.
                if (Enable.ToBool())
                {
                    specObj.Enable();
                }

                specObj.Refresh();
            }
            catch (Exception ex)
            {
                StopFunction(String.Format("Failure creating server audit specification {0} on {1}", specName, target),
                    target: server,
                    errorRecord: new ErrorRecord(ex, "dbatools_NewDbaInstanceAuditSpecification", ErrorCategory.InvalidOperation, server),
                    continueLoop: true);
                continue;
            }

            WriteSpecification(specObj, server);
        }
    }

    // Decorated exactly like Get-DbaInstanceAuditSpecification: the instance triple plus the
    // un-aliased default view. Replace-then-add so a re-emitted object never throws on a duplicate.
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

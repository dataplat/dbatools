#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoAudit = Microsoft.SqlServer.Management.Smo.Audit;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Drops SERVER AUDIT objects. NEW designed command - no PS ancestor, pure C#, no hop.
/// Surface pinned by migration/designed/Remove-DbaInstanceAudit.json (signed 2026-07-21).
///
/// SCOPE. dbatools has shipped Get-DbaInstanceAudit and Copy-DbaInstanceAudit for years and this
/// campaign added New-/Set-DbaInstanceAudit; this fills the DROP gap. The getCounterpart
/// Get-DbaInstanceAudit defines the -InputObject type and the output decoration reproduced below.
///
/// THE CATALOG DOC-COMMENT IS WRONG AND THE COMMAND DOES NOT REPEAT IT. new-commands.md 4.2 says the
/// Drop scripts a force-drop of dependent audit specifications, derived from the Smo/AuditBase.cs
/// doc comment ("Drop an existing Audit with force drop Audit Specifications"). The BODY of ScriptDrop
/// emits a plain 'DROP SERVER AUDIT &lt;name&gt;' with no cascade - so DROP fails server-side while a
/// dependent server/database audit specification still references the audit. This command therefore
/// enumerates the dependents itself, REFUSES the drop with a clear StopFunction listing them when
/// -Force is absent, and drops them first only when -Force is bound. That is exactly what -Force
/// means here.
///
/// ROBUST ENUMERATION. The dependents are found by walking the SMO ServerAuditSpecifications and
/// per-database DatabaseAuditSpecifications collections filtered by AuditName - NOT by
/// Audit.EnumServerAuditSpecification()/EnumDatabaseAuditSpecification(). Those query methods enter
/// EVERY database, so a single inaccessible database (single-user, offline, restoring) throws
/// mid-query and, worse, leaves an open DataReader that poisons every later operation on the
/// connection. A database that cannot be opened is skipped instead of entered.
///
/// DISABLE BEFORE DROP. DROP SERVER AUDIT requires STATE=OFF, so an ENABLED audit must be disabled
/// first (the established dbatools pattern - Copy-DbaInstanceAudit does Disable() then Drop()). This is
/// the distinguishing leg: dropping an enabled audit succeeds only because the cmdlet sequences the
/// Disable(); a test that only drops a disabled audit would pass while the bug shipped. Disable() is
/// the separate EnableDisable() path ('ALTER SERVER AUDIT &lt;n&gt; WITH (STATE = OFF)'), not Alter().
/// A dependent specification dropped under -Force is disabled first for the same reason.
///
/// DUALITY. Either -SqlInstance or -InputObject, no parameter sets (new-commands.md 1.2). -Audit is
/// REQUIRED on the -SqlInstance feeder (matching the sibling Set-DbaInstanceAudit's -Audit requirement);
/// it stays mandatory:false on the surface and is enforced at runtime so the signed spec is not violated.
///
/// OUTPUT. Declares [OutputType(Smo.Audit)] and emits the pre-drop snapshot of each audit it dropped,
/// decorated exactly like Get-DbaInstanceAudit (ComputerName/InstanceName/SqlInstance plus the computed
/// FullName/RemoteFullName properties and the 'Enabled as IsEnabled' view) so a caller can log what was
/// removed. The decoration values are captured BEFORE the drop; the emitted object's .State reflects a
/// dropped object, as the signed spec's designNotes anticipate. CONFIRMIMPACT High per the section 1.3
/// Remove- rule and because dropping a server audit destroys the compliance configuration.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaInstanceAudit", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.Audit))]
public sealed class RemoveDbaInstanceAuditCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The name(s) of the server audit(s) to drop. Required when -SqlInstance is used.</summary>
    [Parameter(Position = 2)]
    public string[]? Audit { get; set; }

    /// <summary>SMO Audit object(s) from Get-DbaInstanceAudit.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public SmoAudit[]? InputObject { get; set; }

    /// <summary>Drop dependent server/database audit specifications first instead of refusing.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Duality, no parameter sets (new-commands.md 1.2). Checked here, not in BeginProcessing,
        // because a pipeline-bound InputObject is not in BoundParameters until ProcessRecord.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        if (TestBound(nameof(SqlInstance)))
        {
            if (Audit is null || Audit.Length == 0)
            {
                StopFunction("Audit is required when SqlInstance is specified");
                return;
            }

            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                Server? server = ConnectInstance(instance, "Failure", minimumVersion: 10);
                if (server is null)
                {
                    continue;
                }

                foreach (SmoAudit auditObj in ResolveAudits(server))
                {
                    ProcessAudit(auditObj);
                }
            }
        }

        // Feeder 2: Audit objects piped from Get-DbaInstanceAudit. The parent server is resolved
        // PER RECORD (audit.Parent = Server) - never carried across records.
        foreach (SmoAudit auditObj in InputObject ?? Array.Empty<SmoAudit>())
        {
            ProcessAudit(auditObj);
        }
    }

    // One worker, two feeders (new-commands.md 1.2).
    private void ProcessAudit(SmoAudit auditObj)
    {
        Server? server = auditObj.Parent;
        if (server is null)
        {
            StopFunction(String.Format("Server audit {0} has no parent server", auditObj.Name),
                target: auditObj, category: ErrorCategory.InvalidData, continueLoop: true);
            return;
        }

        string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);

        if (server.VersionMajor < 10)
        {
            StopFunction(String.Format("Server audits require SQL Server 2008 (10.0) or later; {0} is version {1}", target, server.VersionMajor),
                target: auditObj, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        // Enumerate the audit specifications that reference this audit (SMO's DROP does NOT cascade
        // despite its doc comment - DROP SERVER AUDIT fails while any spec still points at it). The
        // enumeration walks the SMO object collections filtered by AuditName rather than the
        // Enum*AuditSpecification() query methods: those enter EVERY database, so a single
        // inaccessible database (single-user, offline, restoring) throws mid-query and leaves an open
        // DataReader that poisons every later operation on this connection. Server specs are
        // server-scoped and always readable; a database we cannot open is skipped, not entered.
        List<ServerAuditSpecification> dependentServerSpecs = new();
        List<DatabaseAuditSpecification> dependentDbSpecs = new();
        List<string> dependents = new();

        try
        {
            foreach (ServerAuditSpecification serverSpec in server.ServerAuditSpecifications)
            {
                if (String.Equals(serverSpec.AuditName, auditObj.Name, StringComparison.OrdinalIgnoreCase))
                {
                    dependentServerSpecs.Add(serverSpec);
                    dependents.Add(String.Format("server audit specification '{0}'", serverSpec.Name));
                }
            }
        }
        catch (Exception ex)
        {
            StopFunction(String.Format("Failure enumerating dependent server audit specifications for server audit {0} on {1}", auditObj.Name, target),
                target: auditObj,
                errorRecord: new ErrorRecord(ex, "dbatools_RemoveDbaInstanceAudit", ErrorCategory.InvalidOperation, auditObj),
                continueLoop: true);
            return;
        }

        foreach (Microsoft.SqlServer.Management.Smo.Database db in server.Databases)
        {
            // A database we cannot open cannot be enumerated safely; skip it rather than crash the
            // connection. If it does carry a dependent spec the server-side DROP still fails and its
            // raw error is surfaced by the drop try/catch below.
            if (!db.IsAccessible)
            {
                continue;
            }

            try
            {
                foreach (DatabaseAuditSpecification dbSpec in db.DatabaseAuditSpecifications)
                {
                    if (String.Equals(dbSpec.AuditName, auditObj.Name, StringComparison.OrdinalIgnoreCase))
                    {
                        dependentDbSpecs.Add(dbSpec);
                        dependents.Add(String.Format("database audit specification '{0}' in database '{1}'",
                            dbSpec.Name, db.Name));
                    }
                }
            }
            catch (Exception ex)
            {
                WriteVerbose(String.Format("Skipping database {0} while enumerating dependent audit specifications: {1}", db.Name, ex.Message));
            }
        }

        if (dependents.Count > 0 && !Force.ToBool())
        {
            StopFunction(String.Format("Server audit {0} on {1} has dependent audit specifications ({2}); use -Force to drop them first",
                    auditObj.Name, target, String.Join(", ", dependents)),
                target: auditObj, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        // ShouldProcess string is VERBATIM from the signed spec's shouldProcessTargets.
        string action = String.Format("Removing server audit {0}", auditObj.Name);
        if (!ShouldProcess(target, action))
        {
            return;
        }

        // Capture the decoration values BEFORE the drop - a dropped SMO object's properties are the
        // last-fetched cache and reading them after Drop() is not guaranteed.
        DecoratedAuditSnapshot snapshot = CaptureSnapshot(auditObj, server);

        try
        {
            if (Force.ToBool())
            {
                DropDependentSpecifications(dependentServerSpecs, dependentDbSpecs);
            }

            // DROP SERVER AUDIT requires STATE=OFF - disable an enabled audit first.
            if (auditObj.Enabled)
            {
                auditObj.Disable();
            }

            auditObj.Drop();
        }
        catch (Exception ex)
        {
            StopFunction(String.Format("Failure dropping server audit {0} on {1}", auditObj.Name, target),
                target: auditObj,
                errorRecord: new ErrorRecord(ex, "dbatools_RemoveDbaInstanceAudit", ErrorCategory.InvalidOperation, auditObj),
                continueLoop: true);
            return;
        }

        WriteObject(snapshot.Emit(auditObj));
    }

    // Drops the dependent server and database audit specifications so the audit itself can be dropped.
    // Only reached when -Force is bound. DROP ... AUDIT SPECIFICATION also requires STATE=OFF, so an
    // enabled specification is disabled first (the same disable-before-drop rule as the audit).
    private void DropDependentSpecifications(List<ServerAuditSpecification> serverSpecs, List<DatabaseAuditSpecification> dbSpecs)
    {
        foreach (ServerAuditSpecification serverSpec in serverSpecs)
        {
            if (serverSpec.Enabled)
            {
                serverSpec.Disable();
            }
            serverSpec.Drop();
        }

        foreach (DatabaseAuditSpecification dbSpec in dbSpecs)
        {
            if (dbSpec.Enabled)
            {
                dbSpec.Disable();
            }
            dbSpec.Drop();
        }
    }

    // Not a lazy iterator ON PURPOSE: a requested-but-missing audit must be REPORTED (warn + continue,
    // terminating under -EnableException), never silently skipped.
    private List<SmoAudit> ResolveAudits(Server server)
    {
        List<SmoAudit> resolved = new();

        foreach (string auditName in Audit ?? Array.Empty<string>())
        {
            SmoAudit? auditObj = server.Audits[auditName];
            if (auditObj is null)
            {
                StopFunction(String.Format("Server audit {0} does not exist on {1}", auditName, server.Name),
                    target: auditName, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            resolved.Add(auditObj);
        }

        return resolved;
    }

    // Decoration matches Get-DbaInstanceAudit (GetDbaInstanceAuditCommand.cs): the instance triple, the
    // two computed FullName/RemoteFullName properties, and the 'Enabled as IsEnabled' default view.
    private DecoratedAuditSnapshot CaptureSnapshot(SmoAudit auditObj, Server server)
    {
        string computerName = Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server);
        string directory = (auditObj.FilePath ?? String.Empty).TrimEnd('\\');
        string fileName = auditObj.FileName ?? String.Empty;
        string fullName = String.Format("{0}\\{1}", directory, fileName);
        string remote = String.Format("\\\\{0}\\{1}", computerName, fullName.Replace(":", "$"));

        return new DecoratedAuditSnapshot
        {
            ComputerName = computerName,
            InstanceName = server.ServiceName,
            SqlInstance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server),
            FullName = fullName,
            RemoteFullName = remote
        };
    }

    private sealed class DecoratedAuditSnapshot
    {
        public string? ComputerName { get; set; }
        public string? InstanceName { get; set; }
        public string? SqlInstance { get; set; }
        public string? FullName { get; set; }
        public string? RemoteFullName { get; set; }

        // Replace-then-add so a re-emitted object (piped in from the getCounterpart, already decorated)
        // never throws on a duplicate member.
        public PSObject Emit(SmoAudit auditObj)
        {
            PSObject wrapped = PSObject.AsPSObject(auditObj);
            ReplaceNoteProperty(wrapped, "ComputerName", ComputerName);
            ReplaceNoteProperty(wrapped, "InstanceName", InstanceName);
            ReplaceNoteProperty(wrapped, "SqlInstance", SqlInstance);
            ReplaceNoteProperty(wrapped, "FullName", FullName);
            ReplaceNoteProperty(wrapped, "RemoteFullName", RemoteFullName);
            ReplaceAliasProperty(wrapped, "IsEnabled", "Enabled");

            OutputHelper.SetDefaultDisplayPropertySet(wrapped,
                "ComputerName", "InstanceName", "SqlInstance", "Name", "IsEnabled", "OnFailure",
                "MaximumFiles", "MaximumFileSize", "MaximumFileSizeUnit", "MaximumRolloverFiles",
                "QueueDelay", "ReserveDiskSpace", "FullName");
            return wrapped;
        }

        private static void ReplaceNoteProperty(PSObject wrapped, string name, object? value)
        {
            if (wrapped.Properties[name] is not null)
            {
                wrapped.Properties.Remove(name);
            }
            wrapped.Properties.Add(new PSNoteProperty(name, value));
        }

        private static void ReplaceAliasProperty(PSObject wrapped, string aliasName, string referencedName)
        {
            if (wrapped.Properties[aliasName] is not null)
            {
                wrapped.Properties.Remove(aliasName);
            }
            wrapped.Properties.Add(new PSAliasProperty(aliasName, referencedName));
        }
    }
}

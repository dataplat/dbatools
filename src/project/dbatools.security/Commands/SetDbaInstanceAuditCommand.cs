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
/// Alters existing SERVER AUDIT objects. NEW designed command - no PS ancestor, pure C#, no hop.
/// Surface pinned by migration/designed/Set-DbaInstanceAudit.json (signed 2026-07-22).
///
/// SCOPE. dbatools has shipped Get-DbaInstanceAudit and Copy-DbaInstanceAudit for years and this
/// campaign added New-/Remove-DbaInstanceAudit; this fills the ALTER gap. The getCounterpart
/// Get-DbaInstanceAudit defines the output shape reproduced below.
///
/// THE STATE=OFF SEQUENCE IS THE CMDLET'S JOB, NOT SMO'S - the signature gotcha of this row.
/// new-commands.md 4.2 says ALTER SERVER AUDIT requires STATE=OFF, and the spec proves SMO does NOT
/// sequence it: in Smo/AuditBase.cs the STATE clause is emitted ONLY inside the create branch; the
/// alter branch adds the bare statement with no STATE handling, and Alter() goes straight to
/// AlterImpl(). Enable()/Disable() route to a completely separate hand-rolled EnableDisable() path
/// ('ALTER SERVER AUDIT &lt;n&gt; WITH (STATE = ON|OFF)') never called from Alter(). So this cmdlet
/// itself captures Enabled, Disable()s an enabled audit before mutating, Alter()s, then restores the
/// state - and restores the original state if the Alter throws. This gets its own integration test
/// against an ENABLED audit; a test that only alters a disabled audit would pass while the bug shipped.
///
/// ENABLE AND DISABLE ARE TWO SWITCHES, NOT ONE. Because Enabled is access='Read' (Audit.xml:34) the
/// state is driven by Enable()/Disable() methods, not a settable property, so the tri-state cannot ride
/// on a single -Enable:$false. -Enable and -Disable are mutually exclusive (StopFunction when both bound);
/// when NEITHER is bound the audit's state is preserved across the Disable/Alter/Enable sequence.
///
/// RENAME IS A SEPARATE DDL ROUND-TRIP, NOT PART OF Alter(). Rename() routes through RenameImpl and its
/// own ScriptRename ('ALTER SERVER AUDIT &lt;n&gt; MODIFY NAME = &lt;new&gt;'), unreachable from ScriptAlter.
/// So -NewName drives a SECOND statement with its OWN ShouldProcess target so -WhatIf shows both and the
/// user sees the operations are not atomic together. Renaming IS supported here (unlike the audit
/// SPECIFICATION commands) because Audit.Name is not read_only_after_creation.
///
/// TWO TYPING TRAPS from the spec: MaximumRolloverFiles is bigint -&gt; System.Int64 while MaximumFiles is
/// int -&gt; System.Int32 (casts at Smo/AuditBase.cs:579); typing them alike would silently truncate. There
/// is NO AuditGuid property and Guid is read_only_after_creation (Audit.xml:35), create-only, so no -Guid.
///
/// VERSION/EDITION GUARDS (same as New-DbaInstanceAudit, enforced for the InputObject feeder too, which
/// does not pass through the minimumVersion connect). ScriptAudit opens with ThrowIfBelowVersion100
/// (SQL 2008+), matching -MinimumVersion 10. -Filter and the FailOperation failure action additionally
/// require version 110 AND the Standalone engine, -MaximumFiles requires 110, and the Url/ExternalMonitor
/// destinations are Managed-Instance/serverless only. The cmdlet checks these and StopFunctions gracefully.
///
/// DUALITY. Either -SqlInstance or -InputObject, no parameter sets (new-commands.md 1.2). -Audit is
/// REQUIRED on the -SqlInstance feeder (matching the sibling Set-DbaServerRole's -ServerRole requirement);
/// it stays mandatory:false on the surface and is enforced at runtime so the signed spec is not violated.
///
/// OUTPUT. Re-emits the refreshed Smo.Audit decorated exactly like Get-DbaInstanceAudit with
/// ComputerName/InstanceName/SqlInstance plus the two computed FullName/RemoteFullName properties and the
/// 'Enabled as IsEnabled' default view, so Get -&gt; Set -&gt; Get composes. Setting an option to its current
/// value is a genuine no-op (dirty-gated by SMO); the cmdlet still emits the refreshed object and does not
/// claim a change it did not make. CONFIRMIMPACT Medium because altering transiently disables a running
/// audit - auditing stops for the duration, a compliance-relevant side effect a user can intercept.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaInstanceAudit", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.Audit))]
public sealed class SetDbaInstanceAuditCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The name(s) of the server audit(s) to alter. Required when -SqlInstance is used.</summary>
    [Parameter(Position = 2)]
    public string[]? Audit { get; set; }

    /// <summary>SMO Audit object(s) from Get-DbaInstanceAudit.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public SmoAudit[]? InputObject { get; set; }

    /// <summary>Where the audit writes: File, SecurityLog, ApplicationLog, Url or ExternalMonitor.</summary>
    [Parameter]
    public AuditDestinationType DestinationType { get; set; }

    /// <summary>Disable the audit. Mutually exclusive with -Enable.</summary>
    [Parameter]
    public SwitchParameter Disable { get; set; }

    /// <summary>Enable the audit. Mutually exclusive with -Disable.</summary>
    [Parameter]
    public SwitchParameter Enable { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>The target directory for the File destination.</summary>
    [Parameter]
    public string? FilePath { get; set; }

    /// <summary>A raw audit predicate expression. Passed through verbatim (trust boundary). Requires SQL 2012+ standalone.</summary>
    [Parameter]
    public string? Filter { get; set; }

    /// <summary>Maximum size of each audit file (with -MaximumFileSizeUnit).</summary>
    [Parameter]
    public int MaximumFileSize { get; set; }

    /// <summary>The unit for -MaximumFileSize: Mb, Gb or Tb.</summary>
    [Parameter]
    public AuditFileSizeUnit MaximumFileSizeUnit { get; set; }

    /// <summary>Maximum number of audit files to retain (MAX_FILES). Requires SQL 2012+.</summary>
    [Parameter]
    public int MaximumFiles { get; set; }

    /// <summary>Maximum number of rollover files to retain (MAX_ROLLOVER_FILES). bigint.</summary>
    [Parameter]
    public long MaximumRolloverFiles { get; set; }

    /// <summary>Renames the audit. A SECOND statement against the server, not part of the alter.</summary>
    [Parameter]
    public string? NewName { get; set; }

    /// <summary>What the server does when the audit cannot write: Continue, Shutdown or FailOperation.</summary>
    [Parameter]
    public OnFailureAction OnFailure { get; set; }

    /// <summary>Time in milliseconds before audit actions are forced to be processed (QUEUE_DELAY).</summary>
    [Parameter]
    public int QueueDelay { get; set; }

    /// <summary>Reserve the maximum file size on disk up front (RESERVE_DISK_SPACE).</summary>
    [Parameter]
    public SwitchParameter ReserveDiskSpace { get; set; }

    // The option parameters that drive an ALTER (state/rename are handled separately).
    private static readonly string[] OptionParameters =
    {
        nameof(DestinationType), nameof(FilePath), nameof(Filter), nameof(MaximumFileSize),
        nameof(MaximumFileSizeUnit), nameof(MaximumFiles), nameof(MaximumRolloverFiles),
        nameof(OnFailure), nameof(QueueDelay), nameof(ReserveDiskSpace)
    };

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

        // -Enable and -Disable are mutually exclusive (two switches carry the tri-state).
        if (TestBound(nameof(Enable)) && TestBound(nameof(Disable)))
        {
            StopFunction("You cannot specify both -Enable and -Disable");
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
        int major = server.VersionMajor;
        bool standalone = server.DatabaseEngineType == DatabaseEngineType.Standalone;

        // Version/edition guards - validated before any Alter so a bad request is reported without a
        // half-mutated object. Enforced here for the InputObject feeder too, which never passes through
        // the minimumVersion connect.
        if (major < 10)
        {
            StopFunction(String.Format("Altering a server audit requires SQL Server 2008 (10.0) or later; {0} is version {1}", target, major),
                target: auditObj, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        if ((DestinationType == AuditDestinationType.Url || DestinationType == AuditDestinationType.ExternalMonitor)
            && TestBound(nameof(DestinationType))
            && server.DatabaseEngineEdition != DatabaseEngineEdition.SqlManagedInstance
            && server.DatabaseEngineEdition != DatabaseEngineEdition.SqlOnDemand)
        {
            StopFunction(String.Format("The {0} destination is only supported on Azure SQL Managed Instance or serverless targets", DestinationType),
                target: auditObj, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        if (TestBound(nameof(Filter)) && (major < 11 || !standalone))
        {
            StopFunction(String.Format("The -Filter option requires SQL Server 2012 (11.0) or later on a standalone engine; {0} is version {1}", target, major),
                target: auditObj, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        if (TestBound(nameof(OnFailure)) && OnFailure == OnFailureAction.FailOperation && (major < 11 || !standalone))
        {
            StopFunction(String.Format("The FailOperation failure action requires SQL Server 2012 (11.0) or later on a standalone engine; {0} is version {1}", target, major),
                target: auditObj, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        if (TestBound(nameof(MaximumFiles)) && major < 11)
        {
            StopFunction(String.Format("The -MaximumFiles option requires SQL Server 2012 (11.0) or later; {0} is version {1}", target, major),
                target: auditObj, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        bool optionBound = TestBound(OptionParameters);
        bool stateBound = TestBound(nameof(Enable)) || TestBound(nameof(Disable));

        // The alter block (option mutation + state) gets the "Altering" ShouldProcess target;
        // the rename gets its OWN below so -WhatIf shows both operations.
        if (optionBound || stateBound)
        {
            // ShouldProcess strings are VERBATIM from the signed spec's shouldProcessTargets.
            string alterAction = String.Format("Altering server audit {0}", auditObj.Name);
            if (ShouldProcess(target, alterAction))
            {
                bool originalEnabled = auditObj.Enabled;
                bool desiredEnabled = originalEnabled;
                if (TestBound(nameof(Enable)))
                {
                    desiredEnabled = true;
                }
                else if (TestBound(nameof(Disable)))
                {
                    desiredEnabled = false;
                }

                try
                {
                    if (optionBound)
                    {
                        // ALTER SERVER AUDIT requires STATE=OFF - SMO does not sequence this, so an
                        // enabled audit must be disabled before its options can be altered.
                        if (auditObj.Enabled)
                        {
                            auditObj.Disable();
                        }

                        if (TestBound(nameof(DestinationType)))
                        {
                            auditObj.DestinationType = DestinationType;
                        }
                        if (TestBound(nameof(FilePath)))
                        {
                            auditObj.FilePath = FilePath;
                        }
                        if (TestBound(nameof(Filter)))
                        {
                            auditObj.Filter = Filter;
                        }
                        if (TestBound(nameof(MaximumFileSize)))
                        {
                            auditObj.MaximumFileSize = MaximumFileSize;
                        }
                        if (TestBound(nameof(MaximumFileSizeUnit)))
                        {
                            auditObj.MaximumFileSizeUnit = MaximumFileSizeUnit;
                        }
                        if (TestBound(nameof(MaximumFiles)))
                        {
                            auditObj.MaximumFiles = MaximumFiles;
                        }
                        if (TestBound(nameof(MaximumRolloverFiles)))
                        {
                            auditObj.MaximumRolloverFiles = MaximumRolloverFiles;
                        }
                        if (TestBound(nameof(OnFailure)))
                        {
                            auditObj.OnFailure = OnFailure;
                        }
                        if (TestBound(nameof(QueueDelay)))
                        {
                            auditObj.QueueDelay = QueueDelay;
                        }
                        if (TestBound(nameof(ReserveDiskSpace)))
                        {
                            auditObj.ReserveDiskSpace = ReserveDiskSpace.ToBool();
                        }

                        auditObj.Alter();
                    }

                    // Restore/apply the desired state. When neither -Enable nor -Disable was bound this
                    // re-enables an audit the option alter transiently disabled (state preserved).
                    if (desiredEnabled && !auditObj.Enabled)
                    {
                        auditObj.Enable();
                    }
                    else if (!desiredEnabled && auditObj.Enabled)
                    {
                        auditObj.Disable();
                    }
                }
                catch (Exception ex)
                {
                    // Restore the original running state so a failed alter does not leave auditing off.
                    try
                    {
                        if (originalEnabled && !auditObj.Enabled)
                        {
                            auditObj.Enable();
                        }
                    }
                    catch (Exception)
                    {
                        // Best-effort restore; the primary failure is reported below.
                    }

                    StopFunction(String.Format("Failure altering server audit {0} on {1}", auditObj.Name, target),
                        target: auditObj,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaInstanceAudit", ErrorCategory.InvalidOperation, auditObj),
                        continueLoop: true);
                    return;
                }
            }
        }

        if (TestBound(nameof(NewName)))
        {
            // The rename is a SECOND round-trip with its OWN ShouldProcess. -WhatIf must show both.
            string renameAction = String.Format("Renaming server audit {0} to {1}", auditObj.Name, NewName);
            if (ShouldProcess(target, renameAction))
            {
                if (String.IsNullOrEmpty(NewName))
                {
                    StopFunction("NewName cannot be empty", target: auditObj,
                        category: ErrorCategory.InvalidArgument, continueLoop: true);
                    return;
                }

                try
                {
                    auditObj.Rename(NewName);
                }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failure renaming server audit {0} on {1}", auditObj.Name, target),
                        target: auditObj,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaInstanceAudit", ErrorCategory.InvalidOperation, auditObj),
                        continueLoop: true);
                    return;
                }
            }
        }

        try
        {
            auditObj.Refresh();
        }
        catch (Exception)
        {
            // A refresh failure must not lose the object the caller just successfully altered.
        }

        WriteAudit(auditObj, server);
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

    // Decorated exactly like Get-DbaInstanceAudit (GetDbaInstanceAuditCommand.cs): the instance triple,
    // the two computed FullName/RemoteFullName properties, and the 'Enabled as IsEnabled' default view.
    // Replace-then-add so a re-emitted object (piped in from the getCounterpart, already decorated)
    // never throws on a duplicate member.
    private void WriteAudit(SmoAudit auditObj, Server server)
    {
        string computerName = Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server);
        string directory = (auditObj.FilePath ?? String.Empty).TrimEnd('\\');
        string fileName = auditObj.FileName ?? String.Empty;
        string fullName = String.Format("{0}\\{1}", directory, fileName);
        string remote = String.Format("\\\\{0}\\{1}", computerName, fullName.Replace(":", "$"));

        PSObject wrapped = PSObject.AsPSObject(auditObj);
        ReplaceNoteProperty(wrapped, "ComputerName", computerName);
        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server));
        ReplaceNoteProperty(wrapped, "FullName", fullName);
        ReplaceNoteProperty(wrapped, "RemoteFullName", remote);
        ReplaceAliasProperty(wrapped, "IsEnabled", "Enabled");

        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
            "ComputerName", "InstanceName", "SqlInstance", "Name", "IsEnabled", "OnFailure",
            "MaximumFiles", "MaximumFileSize", "MaximumFileSizeUnit", "MaximumRolloverFiles",
            "QueueDelay", "ReserveDiskSpace", "FullName");
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

    private static void ReplaceAliasProperty(PSObject wrapped, string aliasName, string referencedName)
    {
        if (wrapped.Properties[aliasName] is not null)
        {
            wrapped.Properties.Remove(aliasName);
        }
        wrapped.Properties.Add(new PSAliasProperty(aliasName, referencedName));
    }
}

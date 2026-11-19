#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoAudit = Microsoft.SqlServer.Management.Smo.Audit;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates SERVER AUDIT objects. NEW designed command - no PS ancestor, pure C#, no hop.
/// Surface pinned by migration/designed/New-DbaInstanceAudit.json (signed 2026-07-21).
///
/// SCOPE. dbatools has shipped Get-DbaInstanceAudit and Copy-DbaInstanceAudit for years but no
/// way to CREATE an audit - verified, no New-/Set-/Remove-DbaInstanceAudit exists in either code
/// repo. The getCounterpart Get-DbaInstanceAudit defines the output shape reproduced below.
///
/// SMO. Audit.Create() (Smo/AuditBase.cs:52, which calls ThrowIfNotSupported(typeof(Audit)) first)
/// followed by Enable() (:120) when -Enable is bound. The Enabled property is access='Read'
/// (Audit.xml:34) so it cannot be assigned - a new audit is created disabled by default (matching
/// the server) and -Enable is a METHOD CALL, not a property set. DestinationType is MANDATORY at
/// create time (ScriptAudit throws PropertyNotSetException("DestinationType") at :328) and FilePath
/// is mandatory for the File destination (:533); neither is a parameter-level [Parameter(Mandatory)]
/// because the SqlInstance/InputObject duality forbids it (new-commands.md 1.2), so the cmdlet
/// validates both with TestBound and StopFunctions with a clear message rather than letting SMO throw.
///
/// TWO TYPING TRAPS from the spec: MaximumRolloverFiles is bigint -&gt; System.Int64 while
/// MaximumFiles is int -&gt; System.Int32 (casts at Smo/AuditBase.cs:579); typing them alike would
/// silently truncate. There is NO AuditGuid property - the SMO property is Guid, read_only_after_creation
/// (Audit.xml:35), create-only, so it gets no parameter.
///
/// VERSION/EDITION GUARDS. ScriptAudit opens with ThrowIfBelowVersion100 (SQL 2008+), matching the
/// -MinimumVersion 10 Get-DbaInstanceAudit connects with. -Filter and the FailOperation failure action
/// additionally require version 110 AND the Standalone engine (Smo/AuditBase.cs:367-368, :502-508),
/// -MaximumFiles requires 110 (min_major 11), and the Url/ExternalMonitor destinations are
/// Managed-Instance/serverless only. The cmdlet checks these and StopFunctions gracefully rather than
/// surfacing raw SMO exceptions.
///
/// INPUTOBJECT TYPE. This is the one command in the batch where -InputObject is NOT the getCounterpart's
/// emitted type (you cannot pipe an existing Smo.Audit into a command that CREATES audits): it is
/// Smo.Server[], following the house precedent set by New-DbaLinkedServer. new-commands.md 1.2's
/// "InputObject is the REAL type the Get- emits" rule governs Set-/Remove-, where the object already exists.
///
/// FILTER IS RAW PREDICATE TEXT passed through to the audit predicate verbatim - it is not an identifier
/// and cannot be parameterised, so it is NOT quoted or escaped (the same documented trust-boundary shape
/// as the DDL -Definition surface, new-commands.md 6.3).
///
/// OUTPUT. Re-emits the refreshed Smo.Audit decorated exactly like Get-DbaInstanceAudit
/// (GetDbaInstanceAuditCommand.cs process body) with ComputerName/InstanceName/SqlInstance plus the two
/// computed FullName/RemoteFullName properties and the 'Enabled as IsEnabled' default view, so
/// Get -&gt; New -&gt; Get composes. Replace-then-add is used rather than Properties.Add (which throws on a
/// duplicate member) to match the sibling Set- precedent. CONFIRMIMPACT Medium per the New- default.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaInstanceAudit", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.Audit))]
public sealed class NewDbaInstanceAuditCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The name(s) of the server audit(s) to create.</summary>
    [Parameter(Position = 2)]
    public string[]? Audit { get; set; }

    /// <summary>SMO Server object(s), typically from Connect-DbaInstance.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public Server[]? InputObject { get; set; }

    /// <summary>Where the audit writes: File, SecurityLog, ApplicationLog, Url or ExternalMonitor. Required.</summary>
    [Parameter]
    public AuditDestinationType DestinationType { get; set; }

    /// <summary>The target directory for the File destination. Required when DestinationType is File.</summary>
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

    /// <summary>What the server does when the audit cannot write: Continue, Shutdown or FailOperation.</summary>
    [Parameter]
    public OnFailureAction OnFailure { get; set; }

    /// <summary>Time in milliseconds before audit actions are forced to be processed (QUEUE_DELAY).</summary>
    [Parameter]
    public int QueueDelay { get; set; }

    /// <summary>Reserve the maximum file size on disk up front (RESERVE_DISK_SPACE).</summary>
    [Parameter]
    public SwitchParameter ReserveDiskSpace { get; set; }

    /// <summary>Enable the audit immediately after creating it (audits are created disabled by default).</summary>
    [Parameter]
    public SwitchParameter Enable { get; set; }

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

        if (Audit is null || Audit.Length == 0)
        {
            StopFunction("You must specify at least one audit name via -Audit");
            return;
        }

        // DestinationType is mandatory at create time; the duality forbids marking it [Parameter(Mandatory)].
        if (!TestBound(nameof(DestinationType)))
        {
            StopFunction("You must specify -DestinationType when creating an audit");
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

    // One worker, two feeders (new-commands.md 1.2).
    private void ProcessServer(Server server)
    {
        string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);
        int major = server.VersionMajor;
        bool standalone = server.DatabaseEngineType == DatabaseEngineType.Standalone;

        // Destination/version/edition guards - validated before any Create so a bad request is
        // reported without a partial object left behind.
        if (DestinationType == AuditDestinationType.File && !TestBound(nameof(FilePath)))
        {
            StopFunction("You must specify -FilePath when DestinationType is File",
                target: server, category: ErrorCategory.InvalidArgument, continueLoop: true);
            return;
        }

        if ((DestinationType == AuditDestinationType.Url || DestinationType == AuditDestinationType.ExternalMonitor)
            && server.DatabaseEngineEdition != DatabaseEngineEdition.SqlManagedInstance
            && server.DatabaseEngineEdition != DatabaseEngineEdition.SqlOnDemand)
        {
            StopFunction(String.Format("The {0} destination is only supported on Azure SQL Managed Instance or serverless targets", DestinationType),
                target: server, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        if (TestBound(nameof(Filter)) && (major < 11 || !standalone))
        {
            StopFunction(String.Format("The -Filter option requires SQL Server 2012 (11.0) or later on a standalone engine; {0} is version {1}", target, major),
                target: server, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        if (TestBound(nameof(OnFailure)) && OnFailure == OnFailureAction.FailOperation && (major < 11 || !standalone))
        {
            StopFunction(String.Format("The FailOperation failure action requires SQL Server 2012 (11.0) or later on a standalone engine; {0} is version {1}", target, major),
                target: server, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        if (TestBound(nameof(MaximumFiles)) && major < 11)
        {
            StopFunction(String.Format("The -MaximumFiles option requires SQL Server 2012 (11.0) or later; {0} is version {1}", target, major),
                target: server, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        foreach (string auditName in Audit!)
        {
            // ShouldProcess string is VERBATIM from the signed spec's shouldProcessTargets and is
            // immutable once the tests merge.
            string action = String.Format("Creating server audit {0}", auditName);
            if (!ShouldProcess(target, action))
            {
                continue;
            }

            SmoAudit auditObj;
            try
            {
                auditObj = new SmoAudit(server, auditName);
                auditObj.DestinationType = DestinationType;
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

                auditObj.Create();

                // Enabled is read-only; -Enable is a method call, not a property set.
                if (Enable.ToBool())
                {
                    auditObj.Enable();
                }

                auditObj.Refresh();
            }
            catch (Exception ex)
            {
                StopFunction(String.Format("Failure creating server audit {0} on {1}", auditName, target),
                    target: server,
                    errorRecord: new ErrorRecord(ex, "dbatools_NewDbaInstanceAudit", ErrorCategory.InvalidOperation, server),
                    continueLoop: true);
                continue;
            }

            WriteAudit(auditObj, server);
        }
    }

    // Decorated exactly like Get-DbaInstanceAudit (GetDbaInstanceAuditCommand.cs): the instance triple,
    // the two computed FullName/RemoteFullName properties, and the 'Enabled as IsEnabled' default view.
    // Replace-then-add so a re-emitted object never throws on a duplicate member.
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

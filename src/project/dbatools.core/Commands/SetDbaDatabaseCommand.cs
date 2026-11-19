#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Alters database-level options that no other Set- command already owns. NEW designed command -
/// no PS ancestor, pure C#, no hop. Surface pinned by migration/designed/Set-DbaDatabase.json
/// (signed 2026-07-22).
///
/// SCOPE. The six options here (AutoClose, AutoCreateStatistics, AutoShrink, AutoUpdateStatistics,
/// PageVerify, TargetRecoveryTime) were each confirmed unclaimed by any existing dbatools command.
/// RecoveryModel is DELIBERATELY EXCLUDED - Set-DbaDbRecoveryModel already owns it; owner alter is
/// Set-DbaDbOwner; compatibility level is Set-DbaDbCompatibility. Exposing any of those twice would
/// create two commands that can disagree.
///
/// SMO. Database.Alter() (Smo/DatabaseBase.cs:1454) applies the property changes. -RollbackImmediate
/// selects the Alter(TerminationClause) overload (:1498) passing
/// TerminationClause.RollbackTransactionsImmediately (enum Smo/DatabaseOptionsBase.cs:565), which
/// emits WITH ROLLBACK IMMEDIATE so an option change that needs exclusive access terminates in-flight
/// user transactions instead of blocking. The Alter(TimeSpan) ROLLBACK AFTER n SECONDS overload
/// (:1512) is NOT exposed in v1. The two statistics options write the Database-level property-bag
/// keys AutoCreateStatisticsEnabled / AutoUpdateStatisticsEnabled (note the member-vs-bag name
/// mismatch called out in the spec: the -AutoCreateStatistics / -AutoUpdateStatistics SWITCHES map
/// to those *Enabled properties). TargetRecoveryTime is SECONDS (SqlEnum/xml/Database.xml:452) and
/// SMO rejects negatives (Smo/DatabaseBase.cs:6338 TargetRecoveryTimeNotNegative), so the cmdlet
/// validates &gt;= 0 before Alter and surfaces it as a graceful stop rather than a raw SmoException.
/// PageVerify=Checksum is rejected on pre-2005 targets (ScriptPageVerify, :6554/:6573) and is
/// surfaced the same way.
///
/// BOOLEAN OPTIONS ARE SWITCHES, per dbatools CLAUDE.md (use [switch], never [bool]). A switch alone
/// cannot express "set this to false", so each option is applied ONLY when BOUND and honours the
/// explicit -AutoClose:$false form via TestBound; an unbound switch leaves the option untouched. This
/// is the only way to keep house style and still expose the tri-state.
///
/// DUALITY. Either -SqlInstance or -InputObject, no parameter sets (new-commands.md 1.2). The check
/// lives in ProcessRecord because a pipeline-bound InputObject does not appear in BoundParameters
/// until then. -ExcludeDatabase applies to the -SqlInstance feeder only, matching Set-DbaDbOwner, and
/// the feeder uses the same include/exclude filter semantics as the getCounterpart Get-DbaDatabase.
///
/// OUTPUT. Re-emits the refreshed Smo.Database decorated exactly like Get-DbaDatabase's default view
/// (GetDbaDatabaseCommand.Scripts.cs:233-236) so Get -&gt; Set -&gt; Get composes. Replace-then-add is
/// used rather than OutputHelper.AddInstanceProperties/AddAliasProperty (which the spec's designNotes
/// name) because a piped-in Get-DbaDatabase object is ALREADY decorated and Properties.Add throws on
/// a duplicate member name - the same reason Set-DbaDbUser and Set-DbaLinkedServerLogin replace. The
/// decoration outcome is identical; recorded as a deliberate sibling-matching deviation in Evidence.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDatabase", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.Database))]
public sealed class SetDbaDatabaseCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to alter. Unbound means every accessible database on the instance.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The database(s) to skip. Applies to the -SqlInstance feeder only.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>SMO Database object(s), typically from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public SmoDatabase[]? InputObject { get; set; }

    /// <summary>Set AUTO_CLOSE. Bound-only; -AutoClose:$false turns it off, unbound leaves it alone.</summary>
    [Parameter]
    public SwitchParameter AutoClose { get; set; }

    /// <summary>Set AUTO_CREATE_STATISTICS. Bound-only tri-state via TestBound.</summary>
    [Parameter]
    public SwitchParameter AutoCreateStatistics { get; set; }

    /// <summary>Set AUTO_SHRINK. Bound-only tri-state via TestBound.</summary>
    [Parameter]
    public SwitchParameter AutoShrink { get; set; }

    /// <summary>Set AUTO_UPDATE_STATISTICS. Bound-only tri-state via TestBound.</summary>
    [Parameter]
    public SwitchParameter AutoUpdateStatistics { get; set; }

    /// <summary>Set the PAGE_VERIFY option (None, TornPageDetection, Checksum).</summary>
    [Parameter]
    public PageVerify PageVerify { get; set; }

    /// <summary>Set TARGET_RECOVERY_TIME in SECONDS. Must be &gt;= 0.</summary>
    [Parameter]
    public int TargetRecoveryTime { get; set; }

    /// <summary>Terminate in-flight user transactions immediately (WITH ROLLBACK IMMEDIATE) rather than blocking.</summary>
    [Parameter]
    public SwitchParameter RollbackImmediate { get; set; }

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
            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                Server? server = ConnectInstance(instance, "Failure");
                if (server is null)
                {
                    continue;
                }

                foreach (SmoDatabase db in ResolveDatabases(server))
                {
                    ProcessDatabase(db);
                }
            }
        }

        // Feeder 2: Database objects piped from Get-DbaDatabase. The parent server is resolved PER
        // RECORD (db.Parent) - never carried across records, never reconnected.
        foreach (SmoDatabase db in InputObject ?? Array.Empty<SmoDatabase>())
        {
            ProcessDatabase(db);
        }
    }

    // One worker, two feeders (new-commands.md 1.2).
    private void ProcessDatabase(SmoDatabase db)
    {
        Server? server = db.Parent;
        if (server is null)
        {
            StopFunction(String.Format("Database {0} has no parent server", db.Name),
                target: db, category: ErrorCategory.InvalidData, continueLoop: true);
            return;
        }

        string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);

        bool alterRequested = TestBound(nameof(AutoClose)) || TestBound(nameof(AutoCreateStatistics))
            || TestBound(nameof(AutoShrink)) || TestBound(nameof(AutoUpdateStatistics))
            || TestBound(nameof(PageVerify)) || TestBound(nameof(TargetRecoveryTime));

        if (alterRequested)
        {
            // Validate before touching the object so a bad value is reported without a partial alter.
            if (TestBound(nameof(TargetRecoveryTime)) && TargetRecoveryTime < 0)
            {
                StopFunction(String.Format("TargetRecoveryTime cannot be negative (got {0})", TargetRecoveryTime),
                    target: db, category: ErrorCategory.InvalidArgument, continueLoop: true);
                return;
            }

            if (TestBound(nameof(PageVerify)) && PageVerify == PageVerify.Checksum && server.VersionMajor < 9)
            {
                StopFunction(String.Format("PAGE_VERIFY CHECKSUM requires SQL Server 2005 or later; {0} is version {1}", target, server.VersionMajor),
                    target: db, category: ErrorCategory.InvalidOperation, continueLoop: true);
                return;
            }

            // ShouldProcess string is VERBATIM from the signed spec's shouldProcessTargets and is
            // immutable once the tests merge.
            string action = String.Format("Altering database {0}", db.Name);
            if (ShouldProcess(target, action))
            {
                try
                {
                    if (TestBound(nameof(AutoClose)))
                    {
                        db.AutoClose = AutoClose.ToBool();
                    }
                    if (TestBound(nameof(AutoCreateStatistics)))
                    {
                        db.AutoCreateStatisticsEnabled = AutoCreateStatistics.ToBool();
                    }
                    if (TestBound(nameof(AutoShrink)))
                    {
                        db.AutoShrink = AutoShrink.ToBool();
                    }
                    if (TestBound(nameof(AutoUpdateStatistics)))
                    {
                        db.AutoUpdateStatisticsEnabled = AutoUpdateStatistics.ToBool();
                    }
                    if (TestBound(nameof(PageVerify)))
                    {
                        db.PageVerify = PageVerify;
                    }
                    if (TestBound(nameof(TargetRecoveryTime)))
                    {
                        db.TargetRecoveryTime = TargetRecoveryTime;
                    }

                    if (RollbackImmediate.ToBool())
                    {
                        db.Alter(TerminationClause.RollbackTransactionsImmediately);
                    }
                    else
                    {
                        db.Alter();
                    }
                }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failure altering database {0} on {1}", db.Name, target),
                        target: db,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaDatabase", ErrorCategory.InvalidOperation, db),
                        continueLoop: true);
                    return;
                }
            }
        }

        try
        {
            db.Refresh();
        }
        catch (Exception)
        {
            // A refresh failure must not lose the object the caller just successfully altered.
        }

        WriteDatabase(db, server);
    }

    // Include/exclude filter semantics matching the getCounterpart Get-DbaDatabase: iterate the
    // instance's databases and keep the ones the caller asked for. A requested-but-missing name is not
    // an error here for the same reason it is not in Get-DbaDatabase - it simply does not match.
    private List<SmoDatabase> ResolveDatabases(Server server)
    {
        List<SmoDatabase> resolved = new();

        foreach (SmoDatabase db in server.Databases)
        {
            if (FilterHelper.IsActive(Database) && !ContainsName(Database!, db.Name))
            {
                continue;
            }

            if (FilterHelper.IsActive(ExcludeDatabase) && ContainsName(ExcludeDatabase!, db.Name))
            {
                continue;
            }

            if (!db.IsAccessible)
            {
                WriteMessage(MessageLevel.Warning, String.Format("{0} is not accessible, skipping", db.Name), target: db);
                continue;
            }

            resolved.Add(db);
        }

        return resolved;
    }

    // Decorated exactly like Get-DbaDatabase's base default view (GetDbaDatabaseCommand.Scripts.cs:
    // 233-236) plus the instance triple. Replace-then-add so a piped, already-decorated object does
    // not throw on Properties.Add.
    private void WriteDatabase(SmoDatabase db, Server server)
    {
        PSObject wrapped = PSObject.AsPSObject(db);
        ReplaceNoteProperty(wrapped, "ComputerName", Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server));
        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server));

        // The "Old as New" aliases from the Get-DbaDatabase default view.
        ReplaceAliasProperty(wrapped, "SizeMB", "Size");
        ReplaceAliasProperty(wrapped, "Compatibility", "CompatibilityLevel");
        ReplaceAliasProperty(wrapped, "Encrypted", "EncryptionEnabled");
        ReplaceAliasProperty(wrapped, "LastFullBackup", "LastBackupDate");
        ReplaceAliasProperty(wrapped, "LastDiffBackup", "LastDifferentialBackupDate");
        ReplaceAliasProperty(wrapped, "LastLogBackup", "LastLogBackupDate");

        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
            "ComputerName", "InstanceName", "SqlInstance", "Name", "Status", "IsAccessible", "RecoveryModel",
            "LogReuseWaitStatus", "SizeMB", "Compatibility", "Collation", "Owner", "Encrypted",
            "LastFullBackup", "LastDiffBackup", "LastLogBackup");
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

    private static bool ContainsName(string[] values, string? name)
    {
        foreach (string value in values)
        {
            if (String.Equals(value, name, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }
}

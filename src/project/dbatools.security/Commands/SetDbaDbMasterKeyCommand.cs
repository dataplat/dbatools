#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Management.Automation;
using System.Security;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;
using SmoMasterKey = Microsoft.SqlServer.Management.Smo.MasterKey;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Alters a database master key: regenerate it, or add/remove its password and service-key
/// encryptions. NEW designed command - no PS ancestor, pure C#, no hop. Surface pinned by
/// migration/designed/Set-DbaDbMasterKey.json (signed 2026-07-21).
///
/// SCOPE. Completes the database master key family (New-/Get-/Remove-/Backup-DbaDbMasterKey exist;
/// no Set- did). The getCounterpart Get-DbaDbMasterKey defines the output shape reproduced below.
///
/// OPERATION-SWITCH DESIGN, FORCED BY THE TYPE. Smo.MasterKey is IDroppable ONLY - it has no Alter(),
/// no settable property (CreateDate/DateLastModified/IsOpen/IsEncryptedByServer are all read-only), so
/// there is nothing a property-based Set- could assign. Every mutation is a distinct SMO method:
/// Regenerate(pw)/Regenerate(pw, force), AddPasswordEncryption(pw)/DropPasswordEncryption(pw),
/// AddServiceKeyEncryption()/DropServiceKeyEncryption(). Each of these bypasses SMO's script/queue
/// pipeline and calls ExecuteNonQuery directly - they run IMMEDIATELY, so -WhatIf gets nothing from
/// SMO and each operation must carry its OWN ShouldProcess. A -WhatIf test that only checked emitted
/// text would pass while the operation really ran; the tests assert the side effect did NOT happen.
///
/// DATA-LOSS PATHS SMO WILL NOT STOP. Two guards are entirely the cmdlet's job:
///  - -Force is meaningful ONLY with -Regenerate (it selects the FORCE variant, which drops every
///    secret the old key could not re-decrypt). Binding -Force alone is a StopFunction, not a no-op.
///  - Dropping the LAST encryption bricks the key. Before any drop the cmdlet reads IsEncryptedByServer
///    (the service-master-key encryption) and counts the password encryptions via EnumKeyEncryptions,
///    and StopFunctions when the drop would leave the key with no encryptor. A database master key can
///    only ever be encrypted by password(s) and/or the service master key, so in its EnumKeyEncryptions
///    table the service-key row reports SymmetricKeyEncryptionType 4 (MasterKey) while every password
///    row falls through to -1 - counting the -1 rows is the password-encryptor count.
///
/// SECRETS. The parameters are SecureString, but every SMO method here takes a plain string password,
/// so the secret is materialised at the call boundary and interpolated into the T-SQL batch - visible
/// to any trace or Extended Events capture on the instance. The SecureString type is not a stronger
/// guarantee than that. Secrets are never emitted in output, verbose or WhatIf text.
///
/// REFRESH BEFORE EMITTING. CreateDate/DateLastModified/IsEncryptedByServer are enumerator-backed and
/// read-only; after a regenerate or an encryption change the cmdlet calls Refresh() so DateLastModified
/// is not the stale pre-operation value and the command does not appear to have done nothing.
///
/// DUALITY. Either -SqlInstance (with -Database/-ExcludeDatabase) or -InputObject (Smo.MasterKey[],
/// matching what Get-DbaDbMasterKey emits and Remove-DbaDbMasterKey's InputObject typing), no parameter
/// sets (new-commands.md 1.2). The check lives in ProcessRecord because a pipeline-bound InputObject
/// does not appear in BoundParameters until then. The -SqlInstance feeder uses the same include/exclude
/// filter semantics as the getCounterpart and skips databases with no master key exactly as Get- does.
///
/// OUTPUT. Re-emits the refreshed Smo.MasterKey decorated exactly like Get-DbaDbMasterKey (the instance
/// triple plus Database, default view ComputerName, InstanceName, SqlInstance, Database, CreateDate,
/// DateLastModified, IsEncryptedByServer) via replace-then-add so a piped, already-decorated object does
/// not throw on a duplicate member. CONFIRMIMPACT High - it is a key operation and matches what
/// New-DbaDbMasterKey and Remove-DbaDbMasterKey already declare.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbMasterKey", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.MasterKey))]
public sealed class SetDbaDbMasterKeyCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) whose master key to alter. Applies to the -SqlInstance feeder.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The database(s) to skip. Applies to the -SqlInstance feeder only.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Master key object(s), typically piped from Get-DbaDbMasterKey.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public SmoMasterKey[]? InputObject { get; set; }

    /// <summary>The new password for -Regenerate. Also the value carried by the -Password alias.</summary>
    [Parameter(Position = 5)]
    [Alias("Password")]
    public SecureString? SecurePassword { get; set; }

    /// <summary>Add a password encryption to the master key.</summary>
    [Parameter]
    public SecureString? AddPasswordEncryption { get; set; }

    /// <summary>Remove a password encryption from the master key. Refused if it is the last encryptor.</summary>
    [Parameter]
    public SecureString? DropPasswordEncryption { get; set; }

    /// <summary>Encrypt the master key by the service master key.</summary>
    [Parameter]
    public SwitchParameter AddServiceKeyEncryption { get; set; }

    /// <summary>Remove the service-master-key encryption. Refused if it is the last encryptor.</summary>
    [Parameter]
    public SwitchParameter DropServiceKeyEncryption { get; set; }

    /// <summary>Regenerate the master key, re-encrypting it with -SecurePassword.</summary>
    [Parameter]
    public SwitchParameter Regenerate { get; set; }

    /// <summary>With -Regenerate, force the regeneration, dropping secrets the old key cannot decrypt.</summary>
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

        // Mutually-exclusive pairs: a single add/drop of the same encryptor kind is contradictory.
        if (TestBound(nameof(AddPasswordEncryption)) && TestBound(nameof(DropPasswordEncryption)))
        {
            StopFunction("-AddPasswordEncryption and -DropPasswordEncryption cannot be used together");
            return;
        }

        if (TestBound(nameof(AddServiceKeyEncryption)) && TestBound(nameof(DropServiceKeyEncryption)))
        {
            StopFunction("-AddServiceKeyEncryption and -DropServiceKeyEncryption cannot be used together");
            return;
        }

        // -Force is meaningful ONLY with -Regenerate; binding it alone is an error, not a silent no-op.
        if (TestBound(nameof(Force)) && !TestBound(nameof(Regenerate)))
        {
            StopFunction("-Force is only meaningful with -Regenerate");
            return;
        }

        // -Regenerate re-encrypts the key with a new password, so that password is required.
        if (TestBound(nameof(Regenerate)) && !TestBound(nameof(SecurePassword)))
        {
            StopFunction("-Regenerate requires -SecurePassword (the new password)");
            return;
        }

        bool anyOperation = TestBound(nameof(Regenerate)) || TestBound(nameof(AddPasswordEncryption))
            || TestBound(nameof(DropPasswordEncryption)) || TestBound(nameof(AddServiceKeyEncryption))
            || TestBound(nameof(DropServiceKeyEncryption));
        if (!anyOperation)
        {
            StopFunction("You must specify at least one operation: -Regenerate, -AddPasswordEncryption, -DropPasswordEncryption, -AddServiceKeyEncryption or -DropServiceKeyEncryption");
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

                foreach (SmoMasterKey masterKey in ResolveMasterKeys(server))
                {
                    ProcessMasterKey(masterKey);
                }
            }
        }

        // Feeder 2: MasterKey objects piped from Get-DbaDbMasterKey. The parent database and server are
        // resolved PER RECORD (masterKey.Parent) - never carried across records, never reconnected.
        foreach (SmoMasterKey masterKey in InputObject ?? Array.Empty<SmoMasterKey>())
        {
            ProcessMasterKey(masterKey);
        }
    }

    // One worker, two feeders (new-commands.md 1.2).
    private void ProcessMasterKey(SmoMasterKey masterKey)
    {
        SmoDatabase? db = masterKey.Parent;
        Server? server = db?.Parent;
        if (db is null || server is null)
        {
            StopFunction(String.Format("Master key {0} has no parent database or server", masterKey.Urn),
                target: masterKey, category: ErrorCategory.InvalidData, continueLoop: true);
            return;
        }

        string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);
        bool changed = false;

        bool dropRequested = TestBound(nameof(DropServiceKeyEncryption)) || TestBound(nameof(DropPasswordEncryption));

        // BRICK GUARD, evaluated BEFORE any mutation (and before ShouldProcess) so a refusal is reported
        // cleanly - not swallowed by the operation catch below - and no half-applied add lands first. A
        // database master key can only be encrypted by password(s) and/or the service master key, so the
        // key is unusable if this invocation would leave it with neither. The check is on the FINAL state
        // the requested add/drop combination would produce, so a drop that a same-call add makes safe is
        // still permitted. EnumKeyEncryptions is only queried when a drop is actually requested.
        if (dropRequested)
        {
            bool serviceAfter = (masterKey.IsEncryptedByServer && !TestBound(nameof(DropServiceKeyEncryption)))
                || TestBound(nameof(AddServiceKeyEncryption));
            int passwordAfter = CountPasswordEncryptions(masterKey)
                + (TestBound(nameof(AddPasswordEncryption)) ? 1 : 0)
                - (TestBound(nameof(DropPasswordEncryption)) ? 1 : 0);
            if (!serviceAfter && passwordAfter <= 0)
            {
                StopFunction(String.Format("Refusing to drop the last encryption on the master key in {0} on {1}: the key would be left with no encryptor and become unusable", db.Name, target),
                    target: masterKey, category: ErrorCategory.InvalidOperation, continueLoop: true);
                return;
            }
        }

        // The encryption add/drop operations share the "Altering encryption" ShouldProcess target from the
        // signed spec. Adds run before drops so a fresh encryptor is in place before an old one is removed.
        if (TestBound(nameof(AddServiceKeyEncryption)) || TestBound(nameof(DropServiceKeyEncryption))
            || TestBound(nameof(AddPasswordEncryption)) || TestBound(nameof(DropPasswordEncryption)))
        {
            string action = String.Format("Altering encryption on database master key in database {0}", db.Name);
            if (ShouldProcess(target, action))
            {
                try
                {
                    if (TestBound(nameof(AddServiceKeyEncryption)))
                    {
                        masterKey.AddServiceKeyEncryption();
                        changed = true;
                    }

                    if (TestBound(nameof(AddPasswordEncryption)))
                    {
                        masterKey.AddPasswordEncryption(SecurePass.ToPlainText(AddPasswordEncryption!));
                        changed = true;
                    }

                    if (TestBound(nameof(DropServiceKeyEncryption)))
                    {
                        masterKey.DropServiceKeyEncryption();
                        changed = true;
                    }

                    if (TestBound(nameof(DropPasswordEncryption)))
                    {
                        masterKey.DropPasswordEncryption(SecurePass.ToPlainText(DropPasswordEncryption!));
                        changed = true;
                    }
                }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failure altering encryption on the master key in {0} on {1}", db.Name, target),
                        target: masterKey,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaDbMasterKey", ErrorCategory.InvalidOperation, masterKey),
                        continueLoop: true);
                    return;
                }
            }
        }

        // Regenerate carries its OWN ShouldProcess target so -WhatIf shows it as a separate operation.
        if (TestBound(nameof(Regenerate)))
        {
            string action = String.Format("Regenerating database master key in database {0}", db.Name);
            if (ShouldProcess(target, action))
            {
                try
                {
                    string newPassword = SecurePass.ToPlainText(SecurePassword!);
                    if (Force.ToBool())
                    {
                        masterKey.Regenerate(newPassword, true);
                    }
                    else
                    {
                        masterKey.Regenerate(newPassword);
                    }
                    changed = true;
                }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failure regenerating the master key in {0} on {1}", db.Name, target),
                        target: masterKey,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaDbMasterKey", ErrorCategory.InvalidOperation, masterKey),
                        continueLoop: true);
                    return;
                }
            }
        }

        // The read-only, enumerator-backed CreateDate/DateLastModified/IsEncryptedByServer only reflect a
        // successful mutation after a refresh; without it the re-emitted object reports stale values.
        if (changed)
        {
            try
            {
                masterKey.Refresh();
            }
            catch (Exception)
            {
                // A refresh failure must not lose the object the caller just successfully altered.
            }
        }

        WriteMasterKey(masterKey, db, server);
    }

    // Include/exclude filter semantics matching the getCounterpart Get-DbaDbMasterKey: iterate the
    // instance's databases, keep the ones the caller asked for, and skip a database with no master key
    // with the same verbose message Get- uses (absence is normal on a broad scan, not an error).
    private List<SmoMasterKey> ResolveMasterKeys(Server server)
    {
        List<SmoMasterKey> resolved = new();

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
                WriteMessage(MessageLevel.Warning, String.Format("Database {0} on {1} is not accessible. Skipping.", db.Name, server.Name), target: db);
                continue;
            }

            SmoMasterKey? masterKey = db.MasterKey;
            if (masterKey is null)
            {
                WriteMessage(MessageLevel.Verbose, String.Format("No master key exists in the {0} database on {1}", db.Name, server.Name), target: db);
                continue;
            }

            resolved.Add(masterKey);
        }

        return resolved;
    }

    // A database master key can only be encrypted by password(s) and/or the service master key. In the
    // EnumKeyEncryptions table the service-key row reports SymmetricKeyEncryptionType 4 (MasterKey); every
    // password row falls through the enumerator's crypt_type map to -1. So the count of -1 rows is the
    // number of password encryptors.
    private static int CountPasswordEncryptions(SmoMasterKey masterKey)
    {
        int count = 0;
        DataTable table = masterKey.EnumKeyEncryptions();
        foreach (DataRow row in table.Rows)
        {
            object value = row["SymmetricKeyEncryptionType"];
            if (value != null && value != DBNull.Value && Convert.ToInt32(value) == -1)
            {
                count++;
            }
        }
        return count;
    }

    // Decorated exactly like Get-DbaDbMasterKey (GetDbaDbMasterKeyCommand.cs:135-140): the instance
    // triple, Database, and the seven-column default view. Replace-then-add so a re-emitted object piped
    // in from the getCounterpart (already decorated) never throws on a duplicate member.
    private void WriteMasterKey(SmoMasterKey masterKey, SmoDatabase db, Server server)
    {
        PSObject wrapped = PSObject.AsPSObject(masterKey);
        ReplaceNoteProperty(wrapped, "ComputerName", Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server));
        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server));
        ReplaceNoteProperty(wrapped, "Database", db.Name);

        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
            "ComputerName", "InstanceName", "SqlInstance", "Database", "CreateDate", "DateLastModified", "IsEncryptedByServer");
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

#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoCertificate = Microsoft.SqlServer.Management.Smo.Certificate;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;
using SmoEncryptionKey = Microsoft.SqlServer.Management.Smo.DatabaseEncryptionKey;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Alters a database encryption key (TDE DEK): regenerate it with a new algorithm, or re-encrypt it by a
/// different certificate/asymmetric key. NEW designed command - no PS ancestor, pure C#, no hop. Surface
/// pinned by migration/designed/Set-DbaDbEncryptionKey.json (signed 2026-07-21).
///
/// SCOPE. Completes the database encryption key family (New-/Get-/Remove-DbaDbEncryptionKey exist; no Set-
/// did). The getCounterpart Get-DbaDbEncryptionKey defines the output shape reproduced below. The DEK is a
/// per-database SINGLETON reached as db.DatabaseEncryptionKey and HAS NO Name, so this command selects by
/// -Database and carries no name parameter.
///
/// OPERATION-SWITCH DESIGN - THE COMMAND DELIBERATELY DOES NOT CALL Alter(). SMO's DatabaseEncryptionKey
/// ScriptAlter concatenates the REGENERATE and ENCRYPTION BY clauses into ONE statement that the engine
/// rejects when both are dirty, and it dereferences the encryptor name unconditionally on a type-only
/// change (a NullReferenceException). Both are upstream SMO defects that Alter() would hit, so the command
/// instead uses the two dedicated single-statement executors: Regenerate(DatabaseEncryptionAlgorithm)
/// emits ALTER DATABASE ENCRYPTION KEY REGENERATE WITH ALGORITHM, and Reencrypt(encryptorName,
/// DatabaseEncryptionType) emits ALTER DATABASE ENCRYPTION KEY ENCRYPTION BY. When a caller asks for an
/// algorithm change AND a re-encrypt, the cmdlet issues them as two ordered operations. Both run
/// IMMEDIATELY via ExecuteNonQuery - there is no SMO scripting phase, so -WhatIf gets nothing from SMO and
/// each operation carries its OWN ShouldProcess; a -WhatIf test that only checked emitted text would pass
/// while the operation really ran, so the tests assert the side effect did NOT happen.
///
/// SETTABLE SURFACE IS EXACTLY THREE PROPERTIES: EncryptionAlgorithm (drives Regenerate), and EncryptorName
/// plus EncryptionType (drive Reencrypt). Everything else on the DEK - EncryptionState, CreateDate,
/// OpenedDate, RegenerateDate, ModifyDate, SetDate, Thumbprint - is read-only and gets no parameter. The
/// algorithm and type are typed as the real SMO enums so values can never drift and PowerShell tab-completes
/// them. Re-encrypting supplies the unbound half from the key's current value, so the single-statement
/// Reencrypt always receives a complete (encryptorName, type) pair.
///
/// CERTIFICATE-BACKUP SAFETY CHECK, CARRIED OVER FROM New-DbaDbEncryptionKey, WITH -Force AS ITS BYPASS.
/// Re-encrypting a DEK to a certificate that has never been backed up is the same unrecoverable-data-loss
/// hazard as creating one against it, so when the resulting EncryptionType is ServerCertificate the command
/// refuses unless the encryptor certificate in master has been backed up (LastBackupDate.Year != 1) or
/// -Force is given. Asymmetric keys are exempt - they are backed up with the database.
///
/// REGENERATE IS SLOW AND ASYNCHRONOUS. Changing the algorithm re-encrypts the entire database;
/// EncryptionState transitions in the background. The cmdlet returns as soon as the ALTER is accepted and
/// does NOT poll to completion - a command that blocks for an unbounded re-encrypt is worse than one that
/// reports honestly and lets the caller watch EncryptionState.
///
/// DUALITY. Either -SqlInstance (with -Database/-ExcludeDatabase) or -InputObject (Smo.DatabaseEncryptionKey[],
/// matching what Get-DbaDbEncryptionKey emits and Remove-DbaDbEncryptionKey's InputObject typing), no
/// parameter sets. The check lives in ProcessRecord because a pipeline-bound InputObject does not appear in
/// BoundParameters until then. The -SqlInstance feeder uses the same include/exclude filter semantics as the
/// getCounterpart and skips databases with no encryption key exactly as Get- does.
///
/// OUTPUT. Re-emits the refreshed Smo.DatabaseEncryptionKey decorated exactly like Get-DbaDbEncryptionKey
/// (the instance triple plus Database - notably NO DatabaseId - default view ComputerName, InstanceName,
/// SqlInstance, Database, CreateDate, EncryptionAlgorithm, EncryptionState, EncryptionType, EncryptorName,
/// ModifyDate, OpenedDate, RegenerateDate, SetDate, Thumbprint) via replace-then-add so a piped,
/// already-decorated object does not throw on a duplicate member. CONFIRMIMPACT High - regenerating a DEK or
/// re-encrypting it to an unbacked-up encryptor can render an encrypted database unrecoverable, and
/// Remove-DbaDbEncryptionKey is already High.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbEncryptionKey", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.DatabaseEncryptionKey))]
public sealed class SetDbaDbEncryptionKeyCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) whose encryption key to alter. Applies to the -SqlInstance feeder.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The database(s) to skip. Applies to the -SqlInstance feeder only.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>The certificate or asymmetric key in master to re-encrypt the key by. Triggers a re-encrypt.</summary>
    [Parameter(Position = 4)]
    [Alias("Certificate", "CertificateName")]
    public string? EncryptorName { get; set; }

    /// <summary>Whether the encryptor is a server certificate or a server asymmetric key. Triggers a re-encrypt.</summary>
    [Parameter(Position = 5)]
    [Alias("Type")]
    public DatabaseEncryptionType EncryptionType { get; set; }

    /// <summary>The new symmetric algorithm for the key. Triggers a regenerate.</summary>
    [Parameter(Position = 6)]
    public DatabaseEncryptionAlgorithm EncryptionAlgorithm { get; set; }

    /// <summary>Encryption key object(s), typically piped from Get-DbaDbEncryptionKey.</summary>
    [Parameter(ValueFromPipeline = true, Position = 7)]
    public SmoEncryptionKey[]? InputObject { get; set; }

    /// <summary>Bypasses the certificate-backup safety check on a re-encrypt to a server certificate.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

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

        // At least one settable property must be supplied, or there is nothing to alter.
        bool anyOperation = TestBound(nameof(EncryptionAlgorithm)) || TestBound(nameof(EncryptorName))
            || TestBound(nameof(EncryptionType));
        if (!anyOperation)
        {
            StopFunction("You must specify at least one operation: -EncryptionAlgorithm, -EncryptorName or -EncryptionType");
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

                foreach (SmoEncryptionKey key in ResolveEncryptionKeys(server))
                {
                    ProcessEncryptionKey(key);
                }
            }
        }

        // Feeder 2: DatabaseEncryptionKey objects piped from Get-DbaDbEncryptionKey. The parent database and
        // server are resolved PER RECORD (key.Parent) - never carried across records, never reconnected.
        foreach (SmoEncryptionKey key in InputObject ?? Array.Empty<SmoEncryptionKey>())
        {
            ProcessEncryptionKey(key);
        }
    }

    // One worker, two feeders.
    private void ProcessEncryptionKey(SmoEncryptionKey key)
    {
        SmoDatabase? db = key.Parent;
        Server? server = db?.Parent;
        if (db is null || server is null)
        {
            StopFunction(String.Format("Encryption key in database {0} has no parent database or server", key.Urn),
                target: key, category: ErrorCategory.InvalidData, continueLoop: true);
            return;
        }

        string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);
        bool changed = false;

        // Regenerate carries its OWN ShouldProcess target so -WhatIf shows it as a distinct operation. It is
        // issued first so an algorithm change lands before any re-encrypt when a caller asks for both.
        if (TestBound(nameof(EncryptionAlgorithm)))
        {
            string action = String.Format("Regenerating database encryption key in database {0} with algorithm {1}", db.Name, EncryptionAlgorithm);
            if (ShouldProcess(target, action))
            {
                try
                {
                    key.Regenerate(EncryptionAlgorithm);
                    changed = true;
                }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failure regenerating the encryption key in {0} on {1}", db.Name, target),
                        target: key,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaDbEncryptionKey", ErrorCategory.InvalidOperation, key),
                        continueLoop: true);
                    return;
                }
            }
        }

        // Re-encrypt: either -EncryptorName or -EncryptionType triggers it; the unbound half keeps the key's
        // current value so the single-statement Reencrypt always gets a complete pair.
        if (TestBound(nameof(EncryptorName)) || TestBound(nameof(EncryptionType)))
        {
            DatabaseEncryptionType finalType = TestBound(nameof(EncryptionType)) ? EncryptionType : key.EncryptionType;
            string finalEncryptor = TestBound(nameof(EncryptorName)) ? EncryptorName! : key.EncryptorName;
            string action = String.Format("Re-encrypting database encryption key in database {0} by {1} {2}", db.Name, finalType, finalEncryptor);
            if (ShouldProcess(target, action))
            {
                // Re-encrypting to a never-backed-up certificate is the same unrecoverable-data-loss hazard
                // New-DbaDbEncryptionKey guards; -Force is the bypass. Asymmetric keys are exempt. The check
                // runs only on a real run - under -WhatIf ShouldProcess returns false and nothing here fires.
                if (finalType == DatabaseEncryptionType.ServerCertificate && !Force.ToBool())
                {
                    SmoCertificate? cert = FindMasterCertificate(server, finalEncryptor);
                    if (cert is not null && cert.LastBackupDate.Year == 1)
                    {
                        StopFunction(String.Format("Certificate ({0}) in master on {1} has not been backed up. Please backup your certificate or use -Force to continue", finalEncryptor, target),
                            target: key, category: ErrorCategory.InvalidOperation, continueLoop: true);
                        return;
                    }
                }

                try
                {
                    key.Reencrypt(finalEncryptor, finalType);
                    changed = true;
                }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failure re-encrypting the encryption key in {0} on {1}", db.Name, target),
                        target: key,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaDbEncryptionKey", ErrorCategory.InvalidOperation, key),
                        continueLoop: true);
                    return;
                }
            }
        }

        // The read-only, enumerator-backed dates and EncryptionState only reflect a successful mutation after
        // a refresh; without it the re-emitted object reports stale values.
        if (changed)
        {
            try
            {
                key.Refresh();
            }
            catch (Exception)
            {
                // A refresh failure must not lose the object the caller just successfully altered.
            }
        }

        WriteEncryptionKey(key, db, server);
    }

    // Include/exclude filter semantics matching the getCounterpart Get-DbaDbEncryptionKey: iterate the
    // instance's databases, keep the ones the caller asked for, and skip a database with no encryption key
    // with the same verbose message Get- uses (absence is normal on a broad scan, not an error).
    private List<SmoEncryptionKey> ResolveEncryptionKeys(Server server)
    {
        List<SmoEncryptionKey> resolved = new();

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

            if (!db.HasDatabaseEncryptionKey)
            {
                WriteMessage(MessageLevel.Verbose, String.Format("No encryption key exists in the {0} database on {1}", db.Name, server.Name), target: db);
                continue;
            }

            resolved.Add(db.DatabaseEncryptionKey);
        }

        return resolved;
    }

    // The encryptor certificate lives in master. A missing certificate returns null and the backup check is
    // skipped - the subsequent Reencrypt fails server-side, exactly as New-DbaDbEncryptionKey's create does.
    private static SmoCertificate? FindMasterCertificate(Server server, string encryptorName)
    {
        SmoDatabase? master = server.Databases["master"];
        if (master is null)
        {
            return null;
        }
        return master.Certificates[encryptorName];
    }

    // Decorated exactly like Get-DbaDbEncryptionKey (GetDbaDbEncryptionKeyCommand.cs:136-141): the instance
    // triple, Database, and the fourteen-column default view. Replace-then-add so a re-emitted object piped
    // in from the getCounterpart (already decorated) never throws on a duplicate member.
    private void WriteEncryptionKey(SmoEncryptionKey key, SmoDatabase db, Server server)
    {
        PSObject wrapped = PSObject.AsPSObject(key);
        ReplaceNoteProperty(wrapped, "ComputerName", Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server));
        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server));
        ReplaceNoteProperty(wrapped, "Database", db.Name);

        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
            "ComputerName", "InstanceName", "SqlInstance", "Database", "CreateDate", "EncryptionAlgorithm",
            "EncryptionState", "EncryptionType", "EncryptorName", "ModifyDate", "OpenedDate", "RegenerateDate",
            "SetDate", "Thumbprint");
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

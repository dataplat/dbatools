#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Security;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoCertificate = Microsoft.SqlServer.Management.Smo.Certificate;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Alters a database certificate: flip its service-broker flag, change its owner, add or
/// re-password its private key, or remove the private key. NEW designed command - no PS
/// ancestor, pure C#, no hop. Surface pinned by migration/designed/Set-DbaDbCertificate.json.
///
/// SCOPE. Completes the database certificate family (New-/Get-/Remove-/Backup-/Restore-/Copy-
/// DbaDbCertificate exist; no Set- did). The getCounterpart Get-DbaDbCertificate is the ONLY
/// member already native C# rather than a PS hop, so it is the structural model reproduced below.
///
/// TWO KINDS OF MUTATION, FORCED BY THE TYPE. Smo.Certificate is ICreatable/IAlterable/IDroppable
/// with NO IScriptable. Its Alter() scripts EXACTLY two things - ActiveForServiceBrokerDialog and
/// an owner change - and nothing else. Every private-key operation is a distinct SMO method that
/// calls ExecuteNonQuery directly (AddPrivateKey / ChangePrivateKeyPassword / RemovePrivateKey),
/// bypassing the script/queue pipeline and running IMMEDIATELY. So -WhatIf gets nothing from SMO
/// and each operation must carry its OWN ShouldProcess; a -WhatIf test that only checked emitted
/// text would pass while the operation really ran, so the tests assert the side effect did NOT
/// happen. Create-only and read-only properties (Subject, ExpirationDate, StartDate, Issuer,
/// Serial, Thumbprint, PrivateKeyEncryptionType, ...) get no parameter: a subject or validity
/// change is a drop-and-recreate.
///
/// PRIVATE-KEY PARAMETER SHAPE. -PrivateKeyPath with -DecryptionPassword adds a private key
/// encrypted by the database master key (AddPrivateKey(path, decryption)); adding -EncryptionPassword
/// switches to AddPrivateKey(path, decryption, encryption), encrypting the key by that password.
/// -DecryptionPassword with -EncryptionPassword and NO -PrivateKeyPath is the ChangePrivateKeyPassword
/// case (old -> new). So the same two secrets serve both operations and -PrivateKeyPath being bound
/// decides which runs. -RemovePrivateKey is mutually exclusive with -PrivateKeyPath.
///
/// -RemovePrivateKey GUARD. Removing a private key is only recoverable from a backup, so beyond
/// ShouldProcess it also gates on ShouldContinue - unless -Force bypasses it. ShouldContinue is not
/// governed by -Confirm or preference variables, so without -Force the operation is un-runnable
/// non-interactively (that is why -Force exists on this surface, per #90).
///
/// SECRETS. The parameters are SecureString, but every SMO method here takes a plain string, so the
/// secret is materialised at the call boundary and interpolated into the T-SQL batch - visible to a
/// trace. Secrets are never emitted in output, verbose or WhatIf text.
///
/// DUALITY. Either -SqlInstance (with -Database/-ExcludeDatabase/-Certificate) or -InputObject
/// (Smo.Certificate[], matching what Get-DbaDbCertificate emits and Remove-DbaDbCertificate's
/// typing), no parameter sets (new-commands.md 1.2). The check lives in ProcessRecord because a
/// pipeline-bound InputObject is not in BoundParameters during BeginProcessing (a BeginProcessing
/// check would wrongly refuse a piped-in certificate); this mirrors the sibling Set-DbaDbMasterKey.
///
/// OUTPUT. Re-emits the refreshed Smo.Certificate decorated exactly like Get-DbaDbCertificate (the
/// instance triple plus Database and DatabaseId - DatabaseId attached but deliberately not in the
/// display set) via replace-then-add so a piped, already-decorated object never throws on a
/// duplicate member. CONFIRMIMPACT Medium - re-passwording or removing a private key is disruptive
/// and reversible from a backup, so it stays below the High of the master-key/DEK siblings.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbCertificate", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(SmoCertificate))]
public sealed class SetDbaDbCertificateCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) whose certificate to alter. Applies to the -SqlInstance feeder.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The database(s) to skip. Applies to the -SqlInstance feeder only.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Alter only the named certificate(s). Applies to the -SqlInstance feeder.</summary>
    [Parameter(Position = 4)]
    public string[]? Certificate { get; set; }

    /// <summary>The new owner (a User, DatabaseRole or ApplicationRole) for the certificate.</summary>
    [Parameter(Position = 5)]
    public string? Owner { get; set; }

    /// <summary>Path to a private-key file to add to the certificate.</summary>
    [Parameter(Position = 6)]
    public string? PrivateKeyPath { get; set; }

    /// <summary>Password that decrypts the private-key file, or the current key password when re-passwording.</summary>
    [Parameter(Position = 7)]
    public SecureString? DecryptionPassword { get; set; }

    /// <summary>Password to encrypt the private key with, or the new key password when re-passwording.</summary>
    [Parameter(Position = 8)]
    public SecureString? EncryptionPassword { get; set; }

    /// <summary>Certificate object(s), typically piped from Get-DbaDbCertificate.</summary>
    [Parameter(ValueFromPipeline = true, Position = 9)]
    public SmoCertificate[]? InputObject { get; set; }

    /// <summary>Set the certificate active (or inactive with :$false) for service broker dialogs.</summary>
    [Parameter]
    public SwitchParameter ActiveForServiceBrokerDialog { get; set; }

    /// <summary>Remove the certificate's private key. Prompts via ShouldContinue unless -Force is used.</summary>
    [Parameter]
    public SwitchParameter RemovePrivateKey { get; set; }

    /// <summary>Bypass the ShouldContinue confirmation on -RemovePrivateKey. No effect on any other path.</summary>
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

        // Adding a key and removing the key in one call is contradictory.
        if (TestBound(nameof(RemovePrivateKey)) && TestBound(nameof(PrivateKeyPath)))
        {
            StopFunction("-RemovePrivateKey and -PrivateKeyPath cannot be used together");
            return;
        }

        // Adding a private key from a file needs the password that decrypts that file.
        if (TestBound(nameof(PrivateKeyPath)) && !TestBound(nameof(DecryptionPassword)))
        {
            StopFunction("-PrivateKeyPath requires -DecryptionPassword (the password that decrypts the key file)");
            return;
        }

        // Re-passwording a private key (no -PrivateKeyPath) needs BOTH the old and the new password;
        // one alone is an incomplete request rather than a silent no-op.
        if (!TestBound(nameof(PrivateKeyPath))
            && (TestBound(nameof(DecryptionPassword)) || TestBound(nameof(EncryptionPassword)))
            && !(TestBound(nameof(DecryptionPassword)) && TestBound(nameof(EncryptionPassword))))
        {
            StopFunction("Changing the private key password requires both -DecryptionPassword (current) and -EncryptionPassword (new)");
            return;
        }

        bool alterRequested = TestBound(nameof(ActiveForServiceBrokerDialog)) || TestBound(nameof(Owner));
        bool addKey = TestBound(nameof(PrivateKeyPath));
        bool changeKeyPassword = !addKey && TestBound(nameof(DecryptionPassword)) && TestBound(nameof(EncryptionPassword));
        bool removeKey = TestBound(nameof(RemovePrivateKey));

        if (!alterRequested && !addKey && !changeKeyPassword && !removeKey)
        {
            StopFunction("You must specify at least one operation: -ActiveForServiceBrokerDialog, -Owner, -PrivateKeyPath, -DecryptionPassword/-EncryptionPassword (re-password), or -RemovePrivateKey");
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

                foreach (SmoCertificate cert in ResolveCertificates(server))
                {
                    ProcessCertificate(cert, alterRequested, addKey, changeKeyPassword, removeKey);
                }
            }
        }

        // Feeder 2: Certificate objects piped from Get-DbaDbCertificate. The parent database and
        // server are resolved PER RECORD (cert.Parent) - never carried across records, never reconnected.
        foreach (SmoCertificate cert in InputObject ?? Array.Empty<SmoCertificate>())
        {
            ProcessCertificate(cert, alterRequested, addKey, changeKeyPassword, removeKey);
        }
    }

    // One worker, two feeders (new-commands.md 1.2).
    private void ProcessCertificate(SmoCertificate cert, bool alterRequested, bool addKey, bool changeKeyPassword, bool removeKey)
    {
        SmoDatabase? db = cert.Parent;
        Server? server = db?.Parent;
        if (db is null || server is null)
        {
            StopFunction(String.Format("Certificate {0} has no parent database or server", cert.Name),
                target: cert, category: ErrorCategory.InvalidData, continueLoop: true);
            return;
        }

        string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);
        bool changed = false;

        // ALTER path - the only two things Certificate.Alter() can change: the service-broker flag
        // (TestBound so -ActiveForServiceBrokerDialog:$false turns it off and an unbound switch leaves
        // it untouched) and the owner. One ShouldProcess, one Alter().
        if (alterRequested)
        {
            string action = String.Format("Altering certificate '{0}' in database {1}", cert.Name, db.Name);
            if (ShouldProcess(target, action))
            {
                try
                {
                    if (TestBound(nameof(ActiveForServiceBrokerDialog)))
                    {
                        cert.ActiveForServiceBrokerDialog = ActiveForServiceBrokerDialog.ToBool();
                    }
                    if (TestBound(nameof(Owner)))
                    {
                        cert.Owner = Owner;
                    }
                    cert.Alter();
                    changed = true;
                }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failure altering certificate '{0}' in {1} on {2}", cert.Name, db.Name, target),
                        target: cert,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaDbCertificate", ErrorCategory.InvalidOperation, cert),
                        continueLoop: true);
                    return;
                }
            }
        }

        // ADD PRIVATE KEY - immediate SMO method, its own ShouldProcess. Two-arg encrypts the key by
        // the database master key; the three-arg overload encrypts it by -EncryptionPassword instead.
        if (addKey)
        {
            string action = String.Format("Adding private key to certificate '{0}' in database {1}", cert.Name, db.Name);
            if (ShouldProcess(target, action))
            {
                try
                {
                    if (TestBound(nameof(EncryptionPassword)))
                    {
                        cert.AddPrivateKey(PrivateKeyPath, SecurePass.ToPlainText(DecryptionPassword!), SecurePass.ToPlainText(EncryptionPassword!));
                    }
                    else
                    {
                        cert.AddPrivateKey(PrivateKeyPath, SecurePass.ToPlainText(DecryptionPassword!));
                    }
                    changed = true;
                }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failure adding private key to certificate '{0}' in {1} on {2}", cert.Name, db.Name, target),
                        target: cert,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaDbCertificate", ErrorCategory.InvalidOperation, cert),
                        continueLoop: true);
                    return;
                }
            }
        }

        // CHANGE PRIVATE KEY PASSWORD - old (-DecryptionPassword) to new (-EncryptionPassword),
        // immediate SMO method, its own ShouldProcess.
        if (changeKeyPassword)
        {
            string action = String.Format("Changing private key password on certificate '{0}' in database {1}", cert.Name, db.Name);
            if (ShouldProcess(target, action))
            {
                try
                {
                    cert.ChangePrivateKeyPassword(SecurePass.ToPlainText(DecryptionPassword!), SecurePass.ToPlainText(EncryptionPassword!));
                    changed = true;
                }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failure changing private key password on certificate '{0}' in {1} on {2}", cert.Name, db.Name, target),
                        target: cert,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaDbCertificate", ErrorCategory.InvalidOperation, cert),
                        continueLoop: true);
                    return;
                }
            }
        }

        // REMOVE PRIVATE KEY - irreversible without a backup. Beyond ShouldProcess it gates on
        // ShouldContinue unless -Force bypasses it (#90); -Force has no effect on any other path.
        if (removeKey)
        {
            string action = String.Format("Removing private key from certificate '{0}' in database {1}", cert.Name, db.Name);
            if (ShouldProcess(target, action))
            {
                string query = String.Format("Remove the private key from certificate '{0}' in database {1} on {2}? This cannot be undone except by re-importing from a backup of the key.", cert.Name, db.Name, target);
                if (Force.ToBool() || ShouldContinue(query, "Remove private key"))
                {
                    try
                    {
                        cert.RemovePrivateKey();
                        changed = true;
                    }
                    catch (Exception ex)
                    {
                        StopFunction(String.Format("Failure removing private key from certificate '{0}' in {1} on {2}", cert.Name, db.Name, target),
                            target: cert,
                            errorRecord: new ErrorRecord(ex, "dbatools_SetDbaDbCertificate", ErrorCategory.InvalidOperation, cert),
                            continueLoop: true);
                        return;
                    }
                }
            }
        }

        // Private-key operations change PrivateKeyEncryptionType (enumerator-backed, read-only); a
        // refresh keeps the re-emitted object from reporting stale values.
        if (changed)
        {
            try
            {
                cert.Refresh();
            }
            catch (Exception)
            {
                // A refresh failure must not lose the object the caller just successfully altered.
            }
        }

        WriteCertificate(cert, db, server);
    }

    // Include/exclude/name filter semantics matching the getCounterpart Get-DbaDbCertificate: iterate
    // the instance's databases, keep the ones the caller asked for, skip inaccessible ones, then keep
    // the certificates whose name matches -Certificate (all of them when -Certificate is not supplied).
    private List<SmoCertificate> ResolveCertificates(Server server)
    {
        List<SmoCertificate> resolved = new();

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

            CertificateCollection? certs = db.Certificates;
            if (certs is null)
            {
                WriteMessage(MessageLevel.Verbose, String.Format("No certificate exists in the {0} database on {1}", db.Name, server.Name), target: db);
                continue;
            }

            foreach (SmoCertificate cert in certs)
            {
                if (FilterHelper.IsActive(Certificate) && !ContainsName(Certificate!, cert.Name))
                {
                    continue;
                }

                resolved.Add(cert);
            }
        }

        return resolved;
    }

    // Decorated exactly like Get-DbaDbCertificate (GetDbaDbCertificateCommand.cs:121-131): the instance
    // triple, Database and DatabaseId (DatabaseId attached but NOT in the display set - it must still be
    // attached or piped objects change shape), and the fourteen-column default view. Replace-then-add so
    // a re-emitted object piped in from the getCounterpart (already decorated) never throws on a member.
    private void WriteCertificate(SmoCertificate cert, SmoDatabase db, Server server)
    {
        PSObject wrapped = PSObject.AsPSObject(cert);
        ReplaceNoteProperty(wrapped, "ComputerName", Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server));
        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server));
        ReplaceNoteProperty(wrapped, "Database", db.Name);
        ReplaceNoteProperty(wrapped, "DatabaseId", db.ID);

        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
            "ComputerName", "InstanceName", "SqlInstance", "Database", "Name", "Subject", "StartDate",
            "ActiveForServiceBrokerDialog", "ExpirationDate", "Issuer", "LastBackupDate", "Owner",
            "PrivateKeyEncryptionType", "Serial");
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

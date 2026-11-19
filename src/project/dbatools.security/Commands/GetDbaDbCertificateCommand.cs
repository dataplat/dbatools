#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves database certificates for auditing encryption configuration.
/// Port of public/Get-DbaDbCertificate.ps1; surface pinned by migration/baselines/Get-DbaDbCertificate.json.
/// The Get-DbaDatabase resolution runs as an inline SMO enumeration (the same
/// SqlInstance/Database/ExcludeDatabase subset the PS source delegated).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaDbCertificate")]
[OutputType(typeof(Certificate))]
public sealed class GetDbaDbCertificateCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Returns certificates from only the named databases.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>Excludes the named databases.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Returns only the named certificates.</summary>
    // sometimes it's text, other times cert
    [Parameter(Position = 4)]
    public object[]? Certificate { get; set; }

    /// <summary>Returns only certificates with the given subjects.</summary>
    [Parameter(Position = 5)]
    public string[]? Subject { get; set; }

    /// <summary>Database objects piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public SmoDatabase[]? InputObject { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        List<SmoDatabase> databases = new();
        if (InputObject is { Length: > 0 })
        {
            databases.AddRange(InputObject);
        }

        if (SqlInstance is { Length: > 0 })
        {
            // PS: $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
            foreach (DbaInstanceParameter instance in SqlInstance)
            {
                Server? server = ConnectInstance(instance, "Failure");
                if (server is null)
                {
                    continue;
                }
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
                    databases.Add(db);
                }
            }
        }

        foreach (SmoDatabase db in databases)
        {
            if (!db.IsAccessible)
            {
                WriteMessage(MessageLevel.Warning, string.Format("{0} is not accessible, skipping", db));
                continue;
            }

            CertificateCollection? certs = db.Certificates;

            if (certs is null)
            {
                // The PS source interpolates a $instance variable that is never assigned in
                // this loop, so the message renders with an empty instance - quirk preserved.
                WriteMessage(MessageLevel.Verbose, string.Format("No certificate exists in the {0} database on {1}", db, ""), target: db);
                continue;
            }

            foreach (Certificate cert in certs)
            {
                if (FilterHelper.IsActive(Certificate) && !ContainsValue(Certificate!, cert.Name))
                {
                    continue;
                }
                if (FilterHelper.IsActive(Subject) && !ContainsName(Subject!, cert.Subject))
                {
                    continue;
                }

                PSObject wrapped = PSObject.AsPSObject(cert);
                ReplaceNoteProperty(wrapped, "ComputerName", GetDatabaseDecoration(db, "ComputerName"));
                ReplaceNoteProperty(wrapped, "InstanceName", GetDatabaseDecoration(db, "InstanceName"));
                ReplaceNoteProperty(wrapped, "SqlInstance", GetDatabaseDecoration(db, "SqlInstance"));
                ReplaceNoteProperty(wrapped, "Database", db.Name);
                ReplaceNoteProperty(wrapped, "DatabaseId", db.ID);

                OutputHelper.SetDefaultDisplayPropertySet(wrapped,
                    "ComputerName", "InstanceName", "SqlInstance", "Database", "Name", "Subject", "StartDate",
                    "ActiveForServiceBrokerDialog", "ExpirationDate", "Issuer", "LastBackupDate", "Owner",
                    "PrivateKeyEncryptionType", "Serial");

                WriteObject(wrapped);
            }
        }
    }

    private static object? GetDatabaseDecoration(SmoDatabase db, string name)
    {
        // Piped Get-DbaDatabase output carries the decoration as a note property; databases
        // resolved inline compute the same value from the parent server.
        object? decorated = SmoServerExtensions.GetPSProperty(db, name);
        if (decorated is not null)
        {
            return decorated;
        }
        Server parent = db.Parent;
        switch (name)
        {
            case "ComputerName":
                return SmoServerExtensions.GetComputerName(parent);
            case "InstanceName":
                return parent.ServiceName;
            default:
                return SmoServerExtensions.GetDomainInstanceName(parent);
        }
    }

    private static bool ContainsName(string[] values, string? name)
    {
        foreach (string value in values)
        {
            if (string.Equals(value, name, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    private static bool ContainsValue(object[] values, string? name)
    {
        foreach (object value in values)
        {
            if (value is not null && string.Equals(value.ToString(), name, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    private static void ReplaceNoteProperty(PSObject wrapped, string name, object? value)
    {
        PSPropertyInfo? existing = wrapped.Properties[name];
        if (existing is PSNoteProperty)
        {
            wrapped.Properties.Remove(name);
        }
        wrapped.Properties.Add(new PSNoteProperty(name, value));
    }
}

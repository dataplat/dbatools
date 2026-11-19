#nullable enable

using System;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// <para type="synopsis">Reports whether an instance hosts an SSIS catalog and how that catalog is configured.</para>
/// <para type="description">Answers two questions in one object: does this instance have an SSIS catalog (SSISDB), and what is it configured to do. The catalog-wide settings - encryption algorithm, retention window, project version cap, logging level and the schema version itself - come back as properties you can hand straight to Set-DbaSsisCatalog.</para>
/// <para type="description">Reads the catalog.catalog_properties view directly with parameterized T-SQL rather than the Integration Services object model, so it works on both PowerShell editions and on Linux. An instance with no SSIS catalog reports a warning and returns nothing, which is the useful answer for a presence check.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisCatalog -SqlInstance sql2019</code>
///   <para>Returns the SSIS catalog configuration on sql2019, or warns if the instance has no catalog.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisCatalog -SqlInstance sql2016, sql2019 | Select-Object SqlInstance, SchemaVersion, EncryptionAlgorithm</code>
///   <para>Compares the catalog schema version and encryption algorithm across two instances.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; $servers | Get-DbaSsisCatalog</code>
///   <para>Pipes a list of instances in and reports only those that actually host a catalog.</para>
/// </example>
[Cmdlet(VerbsCommon.Get, "DbaSsisCatalog")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaSsisCatalogCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // The SSIS catalog schema arrived in SQL 2012, so an older instance is refused with
            // the version message rather than failing later on a missing catalog schema.
            Server server = ConnectInstance(instance, "Failure", minimumVersion: 11);
            if (server == null)
            {
                continue;
            }

            try
            {
                // ConnectionService hands back a Server whose ConnectionContext may still be
                // lazy; SqlConnectionObject is only usable once it has actually connected.
                if (!server.ConnectionContext.IsOpen)
                {
                    server.ConnectionContext.Connect();
                }

                if (!CatalogExists(server))
                {
                    StopFunction($"No SSIS catalog (SSISDB) found on {instance}", target: instance, continueLoop: true);
                    continue;
                }

                PSObject catalog = new();
                OutputHelper.AddInstanceProperties(catalog, server);
                catalog.Properties.Add(new PSNoteProperty("Name", "SSISDB"));
                AddCatalogProperties(server, catalog);
                OutputHelper.InsertTypeName(catalog, "SsisCatalog");
                OutputHelper.SetDefaultDisplayPropertySet(catalog, "ComputerName", "InstanceName", "SqlInstance", "Name", "SchemaVersion", "SchemaBuild", "EncryptionAlgorithm");
                WriteObject(catalog);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction($"Failure retrieving SSIS catalog properties from {instance}", target: instance, exception: ex, continueLoop: true);
            }
        }
    }

    /// <summary>
    /// Presence is asked of the instance rather than of SMO's Databases collection: enumerating
    /// every database to answer a one-name question drags in whatever state the other databases
    /// are in, and a single-user database is enough to poison the shared connection.
    /// </summary>
    private bool CatalogExists(Server server)
    {
        using SqlCommand presence = new("SELECT DB_ID('SSISDB')", server.ConnectionContext.SqlConnectionObject);
        SetActiveCommand(presence);
        try
        {
            object? result = presence.ExecuteScalar();
            return result != null && result is not DBNull;
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    /// <summary>
    /// The pivot is deliberately driven by what the view returns rather than by a fixed list of
    /// the eleven properties present at SCHEMA_VERSION 6: a property added by a later catalog
    /// build would otherwise be silently dropped by the one command whose job is to report what
    /// is there. Three-part naming keeps the connection on whatever database it opened against.
    /// </summary>
    private void AddCatalogProperties(Server server, PSObject catalog)
    {
        using SqlCommand command = new("SELECT property_name, property_value FROM [SSISDB].[catalog].[catalog_properties]", server.ConnectionContext.SqlConnectionObject);
        SetActiveCommand(command);
        try
        {
            using SqlDataReader reader = command.ExecuteReader();
            while (reader.Read())
            {
                object rawName = reader["property_name"];
                if (rawName is DBNull)
                {
                    continue;
                }

                string propertyName = ToPascalCase(Convert.ToString(rawName, CultureInfo.InvariantCulture) ?? string.Empty);
                if (propertyName.Length == 0 || catalog.Properties[propertyName] != null)
                {
                    continue;
                }

                object rawValue = reader["property_value"];
                catalog.Properties.Add(new PSNoteProperty(propertyName, rawValue is DBNull ? null : rawValue));
            }
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    /// <summary>
    /// SERVER_OPERATION_ENCRYPTION_LEVEL becomes ServerOperationEncryptionLevel, so a caller
    /// composes Get onto Set by property name instead of by catalog magic string.
    /// </summary>
    private static string ToPascalCase(string underscored)
    {
        StringBuilder pascal = new();
        foreach (string token in underscored.Split('_'))
        {
            if (token.Length == 0)
            {
                continue;
            }
            pascal.Append(char.ToUpperInvariant(token[0]));
            if (token.Length > 1)
            {
                pascal.Append(token.Substring(1).ToLowerInvariant());
            }
        }
        return pascal.ToString();
    }
}

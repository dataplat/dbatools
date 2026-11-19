#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// <para type="synopsis">Configures the instance-level properties of an SSIS catalog.</para>
/// <para type="description">Sets the retention, cleanup, logging and encryption properties of the SSIS catalog (SSISDB) through catalog.configure_catalog, one call per property supplied, and returns the catalog afterwards in Get-DbaSsisCatalog's shape.</para>
/// <para type="description">All nine settable properties the catalog accepts are exposed. configure_catalog is the only way to reach any of them, so a property the server accepts and this command refused would be a gap with no owner.</para>
/// <para type="description">The bounds the server enforces are mirrored here so a mistake reads as a sentence rather than as a raise: RETENTION_WINDOW is 1 to 3650 days, MAX_PROJECT_VERSIONS is 1 to 9999, SERVER_LOGGING_LEVEL is 0 to 4 or exactly 100 (100 selects the customized level named by -ServerCustomizedLoggingLevel), and DEFAULT_EXECUTION_MODE is 0 or 1.</para>
/// <para type="description">-EncryptionAlgorithm re-encrypts everything the catalog holds and the server refuses it unless SSISDB is in SINGLE_USER mode. The command checks that first and says so; it does not put the database into SINGLE_USER itself, which would disconnect every other session on the instance.</para>
/// <para type="description">Boolean properties are read through bound-parameter presence, not through truthiness: omitting a switch leaves the property alone, -Flag sets it TRUE and -Flag:$false sets it FALSE.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Set-DbaSsisCatalog -SqlInstance sql2019 -RetentionWindow 90 -MaxProjectVersions 5</code>
///   <para>Keeps operation history for 90 days and five versions of each project.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Set-DbaSsisCatalog -SqlInstance sql2019 -OperationCleanupEnabled:$false</code>
///   <para>Turns the operation cleanup job off. The :$false form is what says "set this to false" - omitting the switch leaves it as it was.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Set-DbaSsisCatalog -SqlInstance sql2019 -ServerLoggingLevel 100 -ServerCustomizedLoggingLevel "Nightly"</code>
///   <para>Selects a customized logging level; 100 is the level value that means "use the customized one named here".</para>
/// </example>
[Cmdlet(VerbsCommon.Set, "DbaSsisCatalog", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(PSObject))]
public sealed class SetDbaSsisCatalogCommand : DbaInstanceCmdlet
{
    // sys.databases.user_access: 0 MULTI_USER, 1 SINGLE_USER, 2 RESTRICTED_USER.
    private const int SingleUserAccess = 1;

    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>How many days of operation history the catalog keeps, 1 to 3650.</summary>
    [Parameter(Position = 2)]
    public int RetentionWindow { get; set; }

    /// <summary>How many versions of each project the catalog keeps, 1 to 9999.</summary>
    [Parameter(Position = 3)]
    public int MaxProjectVersions { get; set; }

    /// <summary>The default logging level for executions: 0 None, 1 Basic, 2 Performance, 3 Verbose, 4 RuntimeLineage, or 100 to use the customized level.</summary>
    [Parameter(Position = 4)]
    public int ServerLoggingLevel { get; set; }

    /// <summary>The name of the customized logging level that a -ServerLoggingLevel of 100 selects.</summary>
    [Parameter(Position = 5)]
    public string? ServerCustomizedLoggingLevel { get; set; }

    /// <summary>How much of each operation the catalog encrypts. The server refuses the change while other operations are running.</summary>
    [Parameter(Position = 6)]
    public int ServerOperationEncryptionLevel { get; set; }

    /// <summary>The default execution mode: 0 server, 1 Scale Out.</summary>
    [Parameter(Position = 7)]
    public int DefaultExecutionMode { get; set; }

    /// <summary>The algorithm the catalog encrypts sensitive values with. Requires SSISDB to be in SINGLE_USER mode.</summary>
    [Parameter(Position = 8)]
    [ValidateSet("TRIPLE_DES_3KEY", "AES_128", "AES_192", "AES_256")]
    public string? EncryptionAlgorithm { get; set; }

    /// <summary>Whether the catalog's operation cleanup job runs. Omit to leave it alone; -OperationCleanupEnabled:$false turns it off.</summary>
    [Parameter]
    public SwitchParameter OperationCleanupEnabled { get; set; }

    /// <summary>Whether the catalog's project version cleanup job runs. Omit to leave it alone; -VersionCleanupEnabled:$false turns it off.</summary>
    [Parameter]
    public SwitchParameter VersionCleanupEnabled { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private readonly List<KeyValuePair<string, string>> _properties = new();

    /// <summary>
    /// The bounds are the server's own, from configure_catalog's body, checked here so the caller
    /// gets a sentence naming the range instead of a raise. They are validated before anything
    /// connects because a value out of range is wrong on every instance in the list.
    /// </summary>
    protected override void BeginProcessing()
    {
        if (TestBound(nameof(RetentionWindow)))
        {
            if (RetentionWindow < 1 || RetentionWindow > 3650)
            {
                StopFunction($"-RetentionWindow must be between 1 and 3650 days; {RetentionWindow} is outside what the catalog accepts", category: ErrorCategory.InvalidArgument);
                return;
            }
            _properties.Add(new KeyValuePair<string, string>("RETENTION_WINDOW", RetentionWindow.ToString(CultureInfo.InvariantCulture)));
        }

        if (TestBound(nameof(MaxProjectVersions)))
        {
            if (MaxProjectVersions < 1 || MaxProjectVersions > 9999)
            {
                StopFunction($"-MaxProjectVersions must be between 1 and 9999; {MaxProjectVersions} is outside what the catalog accepts", category: ErrorCategory.InvalidArgument);
                return;
            }
            _properties.Add(new KeyValuePair<string, string>("MAX_PROJECT_VERSIONS", MaxProjectVersions.ToString(CultureInfo.InvariantCulture)));
        }

        if (TestBound(nameof(ServerLoggingLevel)))
        {
            // 100 is not the top of a range - it is the sentinel that says "use the customized
            // level", which is why the test is not a simple 0..100 bound.
            if ((ServerLoggingLevel < 0 || ServerLoggingLevel > 4) && ServerLoggingLevel != 100)
            {
                StopFunction($"-ServerLoggingLevel must be 0, 1, 2, 3, 4 or 100; {ServerLoggingLevel} is not one the catalog accepts", category: ErrorCategory.InvalidArgument);
                return;
            }
            _properties.Add(new KeyValuePair<string, string>("SERVER_LOGGING_LEVEL", ServerLoggingLevel.ToString(CultureInfo.InvariantCulture)));
        }

        if (TestBound(nameof(ServerCustomizedLoggingLevel)))
        {
            _properties.Add(new KeyValuePair<string, string>("SERVER_CUSTOMIZED_LOGGING_LEVEL", ServerCustomizedLoggingLevel!));
        }

        if (TestBound(nameof(ServerOperationEncryptionLevel)))
        {
            _properties.Add(new KeyValuePair<string, string>("SERVER_OPERATION_ENCRYPTION_LEVEL", ServerOperationEncryptionLevel.ToString(CultureInfo.InvariantCulture)));
        }

        if (TestBound(nameof(DefaultExecutionMode)))
        {
            if (DefaultExecutionMode != 0 && DefaultExecutionMode != 1)
            {
                StopFunction($"-DefaultExecutionMode must be 0 (server) or 1 (Scale Out); {DefaultExecutionMode} is not one the catalog accepts", category: ErrorCategory.InvalidArgument);
                return;
            }
            _properties.Add(new KeyValuePair<string, string>("DEFAULT_EXECUTION_MODE", DefaultExecutionMode.ToString(CultureInfo.InvariantCulture)));
        }

        // Read through bound-parameter presence, never through truthiness: an absent switch is
        // false, and setting every unmentioned property to false is data loss, not a style nit.
        if (TestBound(nameof(OperationCleanupEnabled)))
        {
            _properties.Add(new KeyValuePair<string, string>("OPERATION_CLEANUP_ENABLED", BooleanText(OperationCleanupEnabled)));
        }

        if (TestBound(nameof(VersionCleanupEnabled)))
        {
            _properties.Add(new KeyValuePair<string, string>("VERSION_CLEANUP_ENABLED", BooleanText(VersionCleanupEnabled)));
        }

        if (TestBound(nameof(EncryptionAlgorithm)))
        {
            _properties.Add(new KeyValuePair<string, string>("ENCRYPTION_ALGORITHM", EncryptionAlgorithm!));
        }

        if (_properties.Count == 0)
        {
            StopFunction("You must supply at least one catalog property to set", category: ErrorCategory.InvalidArgument);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

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

                // The precondition is checked rather than met: putting SSISDB into SINGLE_USER
                // would disconnect every other session on a shared instance, which is far beyond
                // what changing an algorithm asks for.
                if (TestBound(nameof(EncryptionAlgorithm)) && !IsSingleUser(server))
                {
                    StopFunction($"Changing the encryption algorithm on {instance} requires SSISDB to be in SINGLE_USER mode; it is not, and this command will not set it, because that would disconnect every other session using the catalog", target: instance, continueLoop: true);
                    continue;
                }

                string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);
                StringBuilder action = new("Setting SSIS catalog ");
                for (int index = 0; index < _properties.Count; index++)
                {
                    if (index > 0)
                    {
                        action.Append(", ");
                    }
                    action.Append(_properties[index].Key).Append(" = ").Append(_properties[index].Value);
                }

                if (!ShouldProcess(target, action.ToString()))
                {
                    continue;
                }

                bool configured = true;
                foreach (KeyValuePair<string, string> property in _properties)
                {
                    try
                    {
                        ConfigureCatalog(server, property.Key, property.Value);
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        // configure_catalog is one call per property, so a refused property leaves
                        // the ones already applied in place. Reporting per property is what tells
                        // the caller which half landed.
                        StopFunction($"Failure setting SSIS catalog property {property.Key} to {property.Value} on {instance}", target: instance, exception: ex, continueLoop: true);
                        configured = false;
                    }
                }

                if (configured)
                {
                    EmitCatalog(server);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction($"Failure setting SSIS catalog properties on {instance}", target: instance, exception: ex, continueLoop: true);
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

    private bool IsSingleUser(Server server)
    {
        using SqlCommand command = new("SELECT user_access FROM sys.databases WHERE name = 'SSISDB'", server.ConnectionContext.SqlConnectionObject);
        SetActiveCommand(command);
        try
        {
            object? result = command.ExecuteScalar();
            return result != null && result is not DBNull && Convert.ToInt32(result) == SingleUserAccess;
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    private void ConfigureCatalog(Server server, string propertyName, string propertyValue)
    {
        using SqlCommand command = new("EXEC [SSISDB].[catalog].[configure_catalog] @property_name = @propertyName, @property_value = @propertyValue", server.ConnectionContext.SqlConnectionObject);
        // Setting ENCRYPTION_ALGORITHM re-encrypts every sensitive value in the catalog, which on a
        // catalog of any size outlasts SqlCommand's own 30-second default. The connection's
        // statement timeout is what the caller configured, so it is what this honours.
        command.CommandTimeout = server.ConnectionContext.StatementTimeout;
        command.Parameters.AddWithValue("@propertyName", propertyName);
        command.Parameters.AddWithValue("@propertyValue", propertyValue);

        SetActiveCommand(command);
        try
        {
            command.ExecuteNonQuery();
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    /// <summary>
    /// The catalog is re-emitted in Get-DbaSsisCatalog's shape, pivoted the same way and from the
    /// view rather than from what was just written, so Get -&gt; Set -&gt; Get composes and a property
    /// the server normalised is reported as the server holds it.
    /// </summary>
    private void EmitCatalog(Server server)
    {
        PSObject catalog = new();
        OutputHelper.AddInstanceProperties(catalog, server);
        catalog.Properties.Add(new PSNoteProperty("Name", "SSISDB"));

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

        OutputHelper.InsertTypeName(catalog, "SsisCatalog");
        OutputHelper.SetDefaultDisplayPropertySet(catalog, "ComputerName", "InstanceName", "SqlInstance", "Name", "SchemaVersion", "SchemaBuild", "EncryptionAlgorithm");
        WriteObject(catalog);
    }

    /// <summary>The catalog stores these as the words TRUE and FALSE, not as bits.</summary>
    private static string BooleanText(SwitchParameter flag)
    {
        return flag.ToBool() ? "TRUE" : "FALSE";
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

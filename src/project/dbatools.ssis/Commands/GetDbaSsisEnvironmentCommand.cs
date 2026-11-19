#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// <para type="synopsis">Retrieves SSIS catalog environments from the SSISDB catalog database.</para>
/// <para type="description">Retrieves the environments defined in the SSIS catalog (SSISDB) - the named variable bags a project execution binds to - along with the folder each one lives in and who created it. Use it to discover which environments exist before starting an execution, or to feed environment names into Get-DbaSsisEnvironmentVariable.</para>
/// <para type="description">Reads the catalog.environments view directly with parameterized T-SQL rather than the Integration Services object model, so it works on both PowerShell editions and on Linux. An instance with no SSIS catalog reports a warning and returns nothing.</para>
/// <para type="description">There is no switch for the variables an environment holds: Get-DbaSsisEnvironmentVariable already owns catalog.environment_variables. Pipe this command's output to it rather than asking two commands the same question.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisEnvironment -SqlInstance sql2019</code>
///   <para>Returns every environment in the SSIS catalog on sql2019.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisEnvironment -SqlInstance sql2019 -Folder Finance -Environment Production</code>
///   <para>Returns only the Production environment in the Finance folder. Names are matched exactly, not as patterns.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisEnvironment -SqlInstance sql2019 -Folder Finance | Select-Object FolderName, Name, Description</code>
///   <para>Lists the environments in the Finance folder alongside the folder each one belongs to.</para>
/// </example>
[Cmdlet(VerbsCommon.Get, "DbaSsisEnvironment")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaSsisEnvironmentCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Limits results to environments in the named SSIS catalog folders. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 2)]
    public string[]? Folder { get; set; }

    /// <summary>Limits results to the named environments. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 3)]
    [Alias("Name")]
    public string[]? Environment { get; set; }

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

                List<KeyValuePair<string, object>> queryParameters = new();
                string sql = BuildQuery(queryParameters);

                using SqlCommand command = new(sql, server.ConnectionContext.SqlConnectionObject);
                foreach (KeyValuePair<string, object> parameter in queryParameters)
                {
                    command.Parameters.AddWithValue(parameter.Key, parameter.Value);
                }
                SetActiveCommand(command);
                try
                {
                    using SqlDataReader reader = command.ExecuteReader();
                    while (reader.Read())
                    {
                        PSObject environment = new();
                        OutputHelper.AddInstanceProperties(environment, server);
                        environment.Properties.Add(new PSNoteProperty("EnvironmentId", ValueOrNull(reader["environment_id"])));
                        environment.Properties.Add(new PSNoteProperty("FolderId", ValueOrNull(reader["folder_id"])));
                        environment.Properties.Add(new PSNoteProperty("FolderName", ValueOrNull(reader["folder_name"])));
                        environment.Properties.Add(new PSNoteProperty("Name", ValueOrNull(reader["name"])));
                        environment.Properties.Add(new PSNoteProperty("Description", ValueOrNull(reader["description"])));
                        environment.Properties.Add(new PSNoteProperty("CreatedBySid", ValueOrNull(reader["created_by_sid"])));
                        environment.Properties.Add(new PSNoteProperty("CreatedByName", ValueOrNull(reader["created_by_name"])));
                        environment.Properties.Add(new PSNoteProperty("CreatedTime", ToDbaDateTime(reader["created_time"])));
                        OutputHelper.InsertTypeName(environment, "SsisEnvironment");
                        OutputHelper.SetDefaultDisplayPropertySet(environment, "ComputerName", "InstanceName", "SqlInstance", "FolderName", "Name", "Description", "CreatedByName", "CreatedTime");
                        WriteObject(environment);
                    }
                }
                finally
                {
                    SetActiveCommand(null);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction($"Failure retrieving SSIS environments from {instance}", target: instance, exception: ex, continueLoop: true);
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
    /// Three-part naming keeps the connection on whatever database it opened against, so the
    /// read never has to switch context on a connection the caller may be reusing. The folder is
    /// joined rather than left as folder_id because every catalog procedure that touches an
    /// environment takes the folder name plus the environment name, never the id.
    /// </summary>
    private string BuildQuery(List<KeyValuePair<string, object>> queryParameters)
    {
        StringBuilder sql = new();
        sql.Append("SELECT e.environment_id, e.folder_id, f.name AS folder_name, e.name, e.description,");
        sql.Append(" e.created_by_sid, e.created_by_name, e.created_time");
        sql.Append(" FROM [SSISDB].[catalog].[environments] e");
        sql.Append(" JOIN [SSISDB].[catalog].[folders] f ON f.folder_id = e.folder_id");

        bool hasFilter = AppendNameFilter(sql, queryParameters, "f.name", Folder, "folder", true);
        AppendNameFilter(sql, queryParameters, "e.name", Environment, "environment", !hasFilter);

        sql.Append(" ORDER BY f.name, e.name");
        return sql.ToString();
    }

    private static bool AppendNameFilter(StringBuilder sql, List<KeyValuePair<string, object>> queryParameters, string column, string[]? names, string parameterPrefix, bool first)
    {
        if (!FilterHelper.IsActive(names))
        {
            return false;
        }

        sql.Append(first ? " WHERE " : " AND ");
        sql.Append(column).Append(" IN (");
        int ordinal = 0;
        foreach (string name in names!)
        {
            ordinal++;
            string parameterName = parameterPrefix + ordinal.ToString(CultureInfo.InvariantCulture);
            if (ordinal > 1)
            {
                sql.Append(", ");
            }
            sql.Append('@').Append(parameterName);
            queryParameters.Add(new KeyValuePair<string, object>(parameterName, name));
        }
        sql.Append(')');
        return true;
    }

    private static object? ValueOrNull(object raw)
    {
        return raw is DBNull ? null : raw;
    }

    private static object? ToDbaDateTime(object raw)
    {
        if (raw is DateTimeOffset offsetValue)
        {
            return new DbaDateTime(offsetValue.DateTime);
        }
        if (raw is DateTime dateTimeValue)
        {
            return new DbaDateTime(dateTimeValue);
        }
        return null;
    }
}

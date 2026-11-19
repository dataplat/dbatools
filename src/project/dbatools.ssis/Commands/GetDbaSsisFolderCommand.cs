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
/// <para type="synopsis">Retrieves SSIS catalog folders from the SSISDB catalog database.</para>
/// <para type="description">Retrieves the folders defined in the SSIS catalog (SSISDB), the top-level container that every deployed project and every environment lives in. Use it to discover what is deployed on an instance before publishing a project, to audit who created a folder and when, or to feed folder names into the project and environment commands.</para>
/// <para type="description">Reads the catalog.folders view directly with parameterized T-SQL rather than the Integration Services object model, so it works on both PowerShell editions and on Linux. An instance with no SSIS catalog reports a warning and returns nothing.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisFolder -SqlInstance sql2019</code>
///   <para>Returns every folder in the SSIS catalog on sql2019.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisFolder -SqlInstance sql2019 -Folder Finance, Staging</code>
///   <para>Returns only the Finance and Staging folders. Names are matched exactly, not as patterns.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisFolder -SqlInstance sql2019 | Select-Object Name, FolderId</code>
///   <para>Lists folder names alongside the catalog ids that catalog.create_folder hands back.</para>
/// </example>
[Cmdlet(VerbsCommon.Get, "DbaSsisFolder")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaSsisFolderCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Limits results to the named SSIS catalog folders. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 2)]
    [Alias("Name")]
    public string[]? Folder { get; set; }

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
                        PSObject folder = new();
                        OutputHelper.AddInstanceProperties(folder, server);
                        folder.Properties.Add(new PSNoteProperty("FolderId", ValueOrNull(reader["folder_id"])));
                        folder.Properties.Add(new PSNoteProperty("Name", ValueOrNull(reader["name"])));
                        folder.Properties.Add(new PSNoteProperty("Description", ValueOrNull(reader["description"])));
                        folder.Properties.Add(new PSNoteProperty("CreatedBySid", ValueOrNull(reader["created_by_sid"])));
                        folder.Properties.Add(new PSNoteProperty("CreatedByName", ValueOrNull(reader["created_by_name"])));
                        folder.Properties.Add(new PSNoteProperty("CreatedTime", ToDbaDateTime(reader["created_time"])));
                        OutputHelper.InsertTypeName(folder, "SsisFolder");
                        OutputHelper.SetDefaultDisplayPropertySet(folder, "ComputerName", "InstanceName", "SqlInstance", "Name", "Description", "CreatedByName", "CreatedTime");
                        WriteObject(folder);
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
                StopFunction($"Failure retrieving SSIS folders from {instance}", target: instance, exception: ex, continueLoop: true);
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
    /// read never has to switch context on a connection the caller may be reusing.
    /// </summary>
    private string BuildQuery(List<KeyValuePair<string, object>> queryParameters)
    {
        StringBuilder sql = new();
        sql.Append("SELECT folder_id, name, description, created_by_sid, created_by_name, created_time");
        sql.Append(" FROM [SSISDB].[catalog].[folders]");

        if (FilterHelper.IsActive(Folder))
        {
            sql.Append(" WHERE name IN (");
            int ordinal = 0;
            foreach (string name in Folder!)
            {
                ordinal++;
                string parameterName = "folder" + ordinal.ToString(CultureInfo.InvariantCulture);
                if (ordinal > 1)
                {
                    sql.Append(", ");
                }
                sql.Append('@').Append(parameterName);
                queryParameters.Add(new KeyValuePair<string, object>(parameterName, name));
            }
            sql.Append(')');
        }

        sql.Append(" ORDER BY name");
        return sql.ToString();
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

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
/// <para type="synopsis">Retrieves deployed SSIS projects from the SSISDB catalog database.</para>
/// <para type="description">Retrieves the projects deployed to the SSIS catalog (SSISDB), along with the folder each one lives in, who deployed it and when, and its current validation state. Use it to audit what is deployed on an instance, to confirm a deployment landed, or to discover the folder and project names the execution commands need.</para>
/// <para type="description">Reads the catalog.projects view directly with parameterized T-SQL rather than the Integration Services object model, so it works on both PowerShell editions and on Linux. An instance with no SSIS catalog reports a warning and returns nothing.</para>
/// <para type="description">Deployment history and package contents are opt-in because both grow per project: -IncludeVersion attaches the rows from catalog.object_versions, which keeps up to MAX_PROJECT_VERSIONS entries per project, and -IncludePackage attaches the packages the project deployed.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisProject -SqlInstance sql2019</code>
///   <para>Returns every deployed project in the SSIS catalog on sql2019.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisProject -SqlInstance sql2019 -Folder Finance -Project Ledger</code>
///   <para>Returns only the Ledger project in the Finance folder. Names are matched exactly, not as patterns.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisProject -SqlInstance sql2019 -IncludePackage | Select-Object Name, { $PSItem.Packages.Name }</code>
///   <para>Lists each project alongside the packages it deployed - the only way in the module to discover the package names Start-DbaSsisExecution needs.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisProject -SqlInstance sql2019 -Project Ledger -IncludeVersion</code>
///   <para>Returns the Ledger project with its retained deployment history attached as Versions.</para>
/// </example>
[Cmdlet(VerbsCommon.Get, "DbaSsisProject")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaSsisProjectCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Limits results to projects in the named SSIS catalog folders. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 2)]
    public string[]? Folder { get; set; }

    /// <summary>Limits results to the named projects. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 3)]
    [Alias("Name")]
    public string[]? Project { get; set; }

    /// <summary>Attaches each project's deployment history from catalog.object_versions as a Versions property.</summary>
    [Parameter]
    public SwitchParameter IncludeVersion { get; set; }

    /// <summary>Attaches the packages each project deployed as a Packages property.</summary>
    [Parameter]
    public SwitchParameter IncludePackage { get; set; }

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

                ReadProjects(server, instance);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction($"Failure retrieving SSIS projects from {instance}", target: instance, exception: ex, continueLoop: true);
            }
        }
    }

    private void ReadProjects(Server server, DbaInstanceParameter instance)
    {
        List<KeyValuePair<string, object>> queryParameters = new();
        string sql = BuildQuery(queryParameters);

        // The related reads need the same connection, which cannot serve a second command while a
        // reader is open, so asking for them is what forces the projects to be held. Without a
        // switch the rows still go straight to the pipeline.
        List<PSObject>? pending = IncludeVersion || IncludePackage ? new List<PSObject>() : null;
        Dictionary<long, PSObject> byProjectId = new();

        using (SqlCommand command = new(sql, server.ConnectionContext.SqlConnectionObject))
        {
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
                    PSObject project = BuildProject(reader, server);
                    if (pending == null)
                    {
                        WriteObject(project);
                        continue;
                    }
                    pending.Add(project);
                    byProjectId[Convert.ToInt64(reader["project_id"], CultureInfo.InvariantCulture)] = project;
                }
            }
            finally
            {
                SetActiveCommand(null);
            }
        }

        if (pending == null)
        {
            return;
        }

        if (IncludePackage)
        {
            AttachRelated(server, byProjectId, "Packages",
                          "SELECT package_id, name, package_guid, description, package_format_version, version_major, version_minor, version_build, version_comments, version_guid, project_id, entry_point, validation_status, last_validation_time FROM [SSISDB].[catalog].[packages] ORDER BY name",
                          BuildPackage);
        }

        if (IncludeVersion)
        {
            // object_versions is keyed by object_id across every catalog object type; 20 is the
            // project type, and without that filter an environment's history would join in.
            AttachRelated(server, byProjectId, "Versions",
                          "SELECT object_version_lsn, object_id, object_type, object_name, description, created_by, created_time, restored_by, last_restored_time FROM [SSISDB].[catalog].[object_versions] WHERE object_type = 20 ORDER BY object_version_lsn DESC",
                          BuildVersion);
        }

        foreach (PSObject project in pending)
        {
            WriteObject(project);
        }
    }

    private void AttachRelated(Server server, Dictionary<long, PSObject> byProjectId, string propertyName, string sql, Func<SqlDataReader, Server, PSObject> build)
    {
        Dictionary<long, List<PSObject>> related = new();
        foreach (long projectId in byProjectId.Keys)
        {
            related[projectId] = new List<PSObject>();
        }

        using SqlCommand command = new(sql, server.ConnectionContext.SqlConnectionObject);
        SetActiveCommand(command);
        try
        {
            using SqlDataReader reader = command.ExecuteReader();
            string keyColumn = propertyName == "Packages" ? "project_id" : "object_id";
            while (reader.Read())
            {
                long projectId = Convert.ToInt64(reader[keyColumn], CultureInfo.InvariantCulture);
                if (!related.TryGetValue(projectId, out List<PSObject>? bucket))
                {
                    continue;
                }
                bucket.Add(build(reader, server));
            }
        }
        finally
        {
            SetActiveCommand(null);
        }

        foreach (KeyValuePair<long, PSObject> entry in byProjectId)
        {
            entry.Value.Properties.Add(new PSNoteProperty(propertyName, related[entry.Key].ToArray()));
        }
    }

    private static PSObject BuildProject(SqlDataReader reader, Server server)
    {
        PSObject project = new();
        OutputHelper.AddInstanceProperties(project, server);
        project.Properties.Add(new PSNoteProperty("ProjectId", ValueOrNull(reader["project_id"])));
        project.Properties.Add(new PSNoteProperty("FolderId", ValueOrNull(reader["folder_id"])));
        project.Properties.Add(new PSNoteProperty("FolderName", ValueOrNull(reader["folder_name"])));
        project.Properties.Add(new PSNoteProperty("Name", ValueOrNull(reader["name"])));
        project.Properties.Add(new PSNoteProperty("Description", ValueOrNull(reader["description"])));
        project.Properties.Add(new PSNoteProperty("ProjectFormatVersion", ValueOrNull(reader["project_format_version"])));
        project.Properties.Add(new PSNoteProperty("DeployedBySid", ValueOrNull(reader["deployed_by_sid"])));
        project.Properties.Add(new PSNoteProperty("DeployedByName", ValueOrNull(reader["deployed_by_name"])));
        project.Properties.Add(new PSNoteProperty("LastDeployedTime", ToDbaDateTime(reader["last_deployed_time"])));
        project.Properties.Add(new PSNoteProperty("CreatedTime", ToDbaDateTime(reader["created_time"])));
        project.Properties.Add(new PSNoteProperty("ObjectVersionLsn", ValueOrNull(reader["object_version_lsn"])));
        project.Properties.Add(new PSNoteProperty("ValidationStatus", ValueOrNull(reader["validation_status"])));
        project.Properties.Add(new PSNoteProperty("LastValidationTime", ToDbaDateTime(reader["last_validation_time"])));
        OutputHelper.InsertTypeName(project, "SsisProject");
        OutputHelper.SetDefaultDisplayPropertySet(project, "ComputerName", "InstanceName", "SqlInstance", "FolderName", "Name", "Description", "LastDeployedTime", "ValidationStatus");
        return project;
    }

    private static PSObject BuildPackage(SqlDataReader reader, Server server)
    {
        PSObject package = new();
        OutputHelper.AddInstanceProperties(package, server);
        package.Properties.Add(new PSNoteProperty("PackageId", ValueOrNull(reader["package_id"])));
        package.Properties.Add(new PSNoteProperty("Name", ValueOrNull(reader["name"])));
        package.Properties.Add(new PSNoteProperty("PackageGuid", ValueOrNull(reader["package_guid"])));
        package.Properties.Add(new PSNoteProperty("Description", ValueOrNull(reader["description"])));
        package.Properties.Add(new PSNoteProperty("PackageFormatVersion", ValueOrNull(reader["package_format_version"])));
        package.Properties.Add(new PSNoteProperty("VersionMajor", ValueOrNull(reader["version_major"])));
        package.Properties.Add(new PSNoteProperty("VersionMinor", ValueOrNull(reader["version_minor"])));
        package.Properties.Add(new PSNoteProperty("VersionBuild", ValueOrNull(reader["version_build"])));
        package.Properties.Add(new PSNoteProperty("VersionComments", ValueOrNull(reader["version_comments"])));
        package.Properties.Add(new PSNoteProperty("VersionGuid", ValueOrNull(reader["version_guid"])));
        package.Properties.Add(new PSNoteProperty("ProjectId", ValueOrNull(reader["project_id"])));
        package.Properties.Add(new PSNoteProperty("EntryPoint", ValueOrNull(reader["entry_point"])));
        package.Properties.Add(new PSNoteProperty("ValidationStatus", ValueOrNull(reader["validation_status"])));
        package.Properties.Add(new PSNoteProperty("LastValidationTime", ToDbaDateTime(reader["last_validation_time"])));
        OutputHelper.InsertTypeName(package, "SsisPackage");
        OutputHelper.SetDefaultDisplayPropertySet(package, "ComputerName", "InstanceName", "SqlInstance", "Name", "Description", "EntryPoint", "ValidationStatus");
        return package;
    }

    private static PSObject BuildVersion(SqlDataReader reader, Server server)
    {
        PSObject version = new();
        OutputHelper.AddInstanceProperties(version, server);
        version.Properties.Add(new PSNoteProperty("ObjectVersionLsn", ValueOrNull(reader["object_version_lsn"])));
        version.Properties.Add(new PSNoteProperty("ProjectId", ValueOrNull(reader["object_id"])));
        version.Properties.Add(new PSNoteProperty("Name", ValueOrNull(reader["object_name"])));
        version.Properties.Add(new PSNoteProperty("Description", ValueOrNull(reader["description"])));
        version.Properties.Add(new PSNoteProperty("CreatedBy", ValueOrNull(reader["created_by"])));
        version.Properties.Add(new PSNoteProperty("CreatedTime", ToDbaDateTime(reader["created_time"])));
        version.Properties.Add(new PSNoteProperty("RestoredBy", ValueOrNull(reader["restored_by"])));
        version.Properties.Add(new PSNoteProperty("LastRestoredTime", ToDbaDateTime(reader["last_restored_time"])));
        OutputHelper.InsertTypeName(version, "SsisProjectVersion");
        OutputHelper.SetDefaultDisplayPropertySet(version, "ComputerName", "InstanceName", "SqlInstance", "Name", "ObjectVersionLsn", "Description", "CreatedBy", "CreatedTime");
        return version;
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
    /// joined rather than left as folder_id because every other command in the module addresses a
    /// project by folder name plus project name.
    /// </summary>
    private string BuildQuery(List<KeyValuePair<string, object>> queryParameters)
    {
        StringBuilder sql = new();
        sql.Append("SELECT p.project_id, p.folder_id, f.name AS folder_name, p.name, p.description,");
        sql.Append(" p.project_format_version, p.deployed_by_sid, p.deployed_by_name, p.last_deployed_time,");
        sql.Append(" p.created_time, p.object_version_lsn, p.validation_status, p.last_validation_time");
        sql.Append(" FROM [SSISDB].[catalog].[projects] p");
        sql.Append(" JOIN [SSISDB].[catalog].[folders] f ON f.folder_id = p.folder_id");

        bool hasFilter = AppendNameFilter(sql, queryParameters, "f.name", Folder, "folder", true);
        AppendNameFilter(sql, queryParameters, "p.name", Project, "project", !hasFilter);

        sql.Append(" ORDER BY f.name, p.name");
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

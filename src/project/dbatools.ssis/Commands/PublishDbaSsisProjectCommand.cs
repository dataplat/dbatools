#nullable enable

using System;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// <para type="synopsis">Deploys an SSIS project (.ispac) to the SSISDB catalog.</para>
/// <para type="description">Deploys a built SSIS project file to a folder in the SSIS catalog (SSISDB) and returns the deployed project. The folder has to exist first - use New-DbaSsisFolder for that - because creating a container for a mistyped name is how a typo becomes a permanent folder.</para>
/// <para type="description">Calls catalog.deploy_project with the project file bound as a varbinary parameter rather than using the Integration Services object model, so it works on both PowerShell editions and on Linux. Deploying over a project that already exists creates a new version rather than replacing the old one; the catalog retains them up to its MAX_PROJECT_VERSIONS setting.</para>
/// <para type="description">The name recorded inside the .ispac must match -Project. The catalog refuses the deployment otherwise, and the reason it gives lives in its operation log rather than in the error it raises - this command reads that log and reports what it says.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Publish-DbaSsisProject -SqlInstance sql2019 -Folder Finance -Project Ledger -Path C:\build\Ledger.ispac</code>
///   <para>Deploys Ledger.ispac into the Finance folder on sql2019 and returns the deployed project.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Publish-DbaSsisProject -SqlInstance sql2019, sql2022 -Folder Finance -Project Ledger -Path C:\build\Ledger.ispac</code>
///   <para>Deploys the same build to both instances, reporting each one separately.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Publish-DbaSsisProject -SqlInstance sql2019 -Folder Finance -Project Ledger -Path C:\build\Ledger.ispac -WhatIf</code>
///   <para>Reports what would be deployed without touching the catalog.</para>
/// </example>
[Cmdlet(VerbsData.Publish, "DbaSsisProject", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(PSObject))]
public sealed partial class PublishDbaSsisProjectCommand : DbaInstanceCmdlet
{
    // catalog.operations.operation_type for a project deployment, and the status it reports when
    // one succeeded. Both are read back after the call because the proc returning without an
    // error is not by itself proof that the project landed.
    private const int DeployOperationType = 101;
    private const int OperationStatusSucceeded = 7;

    private byte[]? projectStream;

    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The existing SSIS catalog folder to deploy into. One project file deploys to exactly one folder, so this is a single name.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public string Folder { get; set; } = null!;

    /// <summary>The name to deploy the project under. It has to match the project name recorded inside the .ispac.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [Alias("Name")]
    public string Project { get; set; } = null!;

    /// <summary>The path to the built .ispac project file. The extension is not enforced - an .ispac is a zip and callers legitimately keep them under other names - but the file must exist and not be empty.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    public string Path { get; set; } = null!;

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>
    /// The file is read before anything connects: an unreadable path is a local failure, and
    /// finding it out after opening a connection and resolving a folder wastes both ends.
    /// </summary>
    protected override void BeginProcessing()
    {
        string resolvedPath;
        try
        {
            resolvedPath = GetUnresolvedProviderPathFromPSPath(Path);
        }
        catch (Exception ex)
        {
            StopFunction($"Failure resolving project file path {Path}", target: Path, exception: ex);
            return;
        }

        FileInfo projectFile = new(resolvedPath);
        if (!projectFile.Exists)
        {
            StopFunction($"Project file {resolvedPath} does not exist", target: Path, category: ErrorCategory.ObjectNotFound);
            return;
        }

        if (projectFile.Length == 0)
        {
            StopFunction($"Project file {resolvedPath} is empty", target: Path, category: ErrorCategory.InvalidData);
            return;
        }

        try
        {
            projectStream = File.ReadAllBytes(resolvedPath);
        }
        catch (Exception ex)
        {
            StopFunction($"Failure reading project file {resolvedPath}", target: Path, exception: ex);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || projectStream == null)
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

                string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);
                if (!ShouldProcess(target, $"Deploying SSIS project {Project} to folder {Folder}"))
                {
                    continue;
                }

                // Anchors the operation log lookup below, so a peer deploying to the same catalog
                // at the same moment cannot have its failure reported as this one's.
                long priorOperationId = ReadLastOperationId(server);

                long operationId;
                try
                {
                    operationId = Deploy(server);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    // The catalog raises a bare "query the operation_messages view for the
                    // operation identifier N" and keeps the actual reason - wrong project name,
                    // unreadable stream, failed validation - in that view. Reporting the raised
                    // text alone would hand the caller a lookup instead of an answer.
                    //
                    // That refusal names the operation, so the read is scoped to it. The id must
                    // postdate the watermark to be this call's; anything else means the number came
                    // from somewhere other than the substitution and is not an id to read by.
                    string reason = TryReadFailedOperationId(ex, out long failedOperationId) && failedOperationId > priorOperationId
                        ? ReadOperationMessages(server, failedOperationId)
                        : ReadOperationMessagesSince(server, priorOperationId);
                    StopDeployment(instance, reason, ex);
                    continue;
                }

                // A deployment can be accepted as a call and still be recorded as failed, so the
                // operation's own outcome decides whether this reports success.
                int status = ReadOperationStatus(server, operationId);
                if (status != OperationStatusSucceeded)
                {
                    // The id is known here, so the messages are this operation's. The ranged read
                    // is for the throw path alone, where no id ever came back.
                    string reason = ReadOperationMessages(server, operationId);
                    StopFunction($"Deployment of SSIS project {Project} to folder {Folder} on {instance} finished with operation status {status}: {reason}", target: instance, continueLoop: true);
                    continue;
                }

                EmitProject(server);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction($"Failure deploying SSIS project {Project} to {instance}", target: instance, exception: ex, continueLoop: true);
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
    /// Reports a refused deployment with the catalog's own explanation, falling back to the raised
    /// text when the catalog logged no operation to explain it - a folder that does not exist, for
    /// instance, is refused before an operation is ever opened, and there the raised text is the
    /// informative one.
    /// <para>The explanation rides the message rather than the exception because the module
    /// registers an exception transform that unwraps anything wrapping a SqlException back down to
    /// it, so a SQL failure always surfaces to the caller as the SqlException itself.</para>
    /// </summary>
    private void StopDeployment(DbaInstanceParameter instance, string reason, Exception ex)
    {
        if (reason.Length == 0)
        {
            reason = ex.Message;
        }

        StopFunction($"Failure deploying SSIS project {Project} to folder {Folder} on {instance}: {reason}", target: instance, exception: ex, continueLoop: true, overrideExceptionMessage: true);
    }

    /// <summary>
    /// The deployed project is re-emitted in Get-DbaSsisProject's shape, decorated identically, so
    /// Publish -&gt; Get pipelines compose. It is read back rather than assembled from what was sent,
    /// because the deployment time and the validation state are the catalog's to report.
    /// </summary>
    private void EmitProject(Server server)
    {
        using SqlCommand command = new("SELECT projects.project_id, projects.folder_id, folders.name AS folder_name, projects.name, projects.description, projects.project_format_version, projects.deployed_by_sid, projects.deployed_by_name, projects.last_deployed_time, projects.created_time, projects.object_version_lsn, projects.validation_status, projects.last_validation_time FROM [SSISDB].[catalog].[projects] projects JOIN [SSISDB].[catalog].[folders] folders ON folders.folder_id = projects.folder_id WHERE folders.name = @folderName AND projects.name = @projectName", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", Folder);
        command.Parameters.AddWithValue("@projectName", Project);

        SetActiveCommand(command);
        try
        {
            using SqlDataReader reader = command.ExecuteReader();
            while (reader.Read())
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
                WriteObject(project);
            }
        }
        finally
        {
            SetActiveCommand(null);
        }
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

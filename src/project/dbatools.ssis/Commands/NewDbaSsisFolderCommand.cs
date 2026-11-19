#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// <para type="synopsis">Creates folders in the SSIS catalog.</para>
/// <para type="description">Creates one or more folders in the SSIS catalog (SSISDB), the top-level container every deployed project and every environment lives in. Nothing can be published to a catalog until a folder exists to publish it into.</para>
/// <para type="description">Calls catalog.create_folder with parameterized T-SQL rather than the Integration Services object model, so it works on both PowerShell editions and on Linux. Each folder is created, emitted and errored independently - one name that already exists does not abort the rest of the call.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; New-DbaSsisFolder -SqlInstance sql2019 -Folder Finance</code>
///   <para>Creates the Finance folder in the SSIS catalog on sql2019 and returns it.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; New-DbaSsisFolder -SqlInstance sql2019 -Folder Finance, Staging -Description "Nightly load"</code>
///   <para>Creates both folders, giving each of them the same description.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; New-DbaSsisFolder -SqlInstance sql2019 -Folder Finance -WhatIf</code>
///   <para>Reports what would be created without touching the catalog.</para>
/// </example>
[Cmdlet(VerbsCommon.New, "DbaSsisFolder", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(PSObject))]
public sealed class NewDbaSsisFolderCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The name or names of the SSIS catalog folders to create.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [Alias("Name")]
    public string[] Folder { get; set; } = null!;

    /// <summary>A description to set on each folder created by this call.</summary>
    [Parameter(Position = 3)]
    public string? Description { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

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

                string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);
                foreach (string folderName in Folder)
                {
                    if (!ShouldProcess(target, $"Creating SSIS folder {folderName}"))
                    {
                        continue;
                    }

                    long folderId;
                    try
                    {
                        folderId = CreateFolder(server, folderName);
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        StopFunction($"Failure creating SSIS folder {folderName} on {instance}", target: instance, exception: ex, continueLoop: true);
                        continue;
                    }

                    // catalog.create_folder takes only the name and the output id, so a description
                    // is a second proc call and the pair is not atomic. A failure here leaves a real
                    // folder behind with an empty description, so it is reported as its own error
                    // rather than as the creation having failed.
                    if (TestBound(nameof(Description)))
                    {
                        try
                        {
                            SetFolderDescription(server, folderName);
                        }
                        catch (PipelineStoppedException)
                        {
                            throw;
                        }
                        catch (Exception ex)
                        {
                            StopFunction($"Created SSIS folder {folderName} on {instance} but failed to set its description", target: instance, exception: ex, continueLoop: true);
                        }
                    }

                    EmitFolder(server, folderId);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction($"Failure creating SSIS folders on {instance}", target: instance, exception: ex, continueLoop: true);
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
    /// The proc hands the new id back on an OUTPUT parameter, so it is read from there rather than
    /// looked up afterwards by name - which is also what makes the read-back below exact even if a
    /// peer is creating folders on the same catalog.
    /// </summary>
    private long CreateFolder(Server server, string folderName)
    {
        using SqlCommand command = new("EXEC [SSISDB].[catalog].[create_folder] @folder_name = @folderName, @folder_id = @folderId OUTPUT", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", folderName);
        SqlParameter folderIdParameter = command.Parameters.Add("@folderId", System.Data.SqlDbType.BigInt);
        folderIdParameter.Direction = System.Data.ParameterDirection.Output;

        SetActiveCommand(command);
        try
        {
            command.ExecuteNonQuery();
        }
        finally
        {
            SetActiveCommand(null);
        }

        return Convert.ToInt64(folderIdParameter.Value, System.Globalization.CultureInfo.InvariantCulture);
    }

    private void SetFolderDescription(Server server, string folderName)
    {
        using SqlCommand command = new("EXEC [SSISDB].[catalog].[set_folder_description] @folder_name = @folderName, @folder_description = @folderDescription", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", folderName);
        command.Parameters.AddWithValue("@folderDescription", (object?)Description ?? DBNull.Value);

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
    /// The created folder is re-emitted in Get-DbaSsisFolder's shape, decorated identically, so
    /// New -&gt; Get pipelines compose. The columns the catalog fills in itself - the creator and the
    /// creation time - are only knowable by reading the row back.
    /// </summary>
    private void EmitFolder(Server server, long folderId)
    {
        using SqlCommand command = new("SELECT folder_id, name, description, created_by_sid, created_by_name, created_time FROM [SSISDB].[catalog].[folders] WHERE folder_id = @folderId", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderId", folderId);

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

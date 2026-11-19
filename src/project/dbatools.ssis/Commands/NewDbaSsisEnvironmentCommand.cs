#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// <para type="synopsis">Creates environments in an SSIS catalog folder.</para>
/// <para type="description">Creates one or more environments in a folder of the SSIS catalog (SSISDB). An environment is the named variable bag a project execution binds to, so it is what lets the same deployed project run against development, test and production values without being redeployed.</para>
/// <para type="description">Calls catalog.create_environment with parameterized T-SQL rather than the Integration Services object model, so it works on both PowerShell editions and on Linux. Each environment is created, emitted and errored independently - one name that already exists does not abort the rest of the call.</para>
/// <para type="description">The folder has to exist first; use New-DbaSsisFolder for that. Variables are added afterwards with New-DbaSsisEnvironmentVariable.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; New-DbaSsisEnvironment -SqlInstance sql2019 -Folder Finance -Environment Production</code>
///   <para>Creates the Production environment in the Finance folder on sql2019 and returns it.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; New-DbaSsisEnvironment -SqlInstance sql2019 -Folder Finance -Environment Development, Test -Description "Nightly load"</code>
///   <para>Creates both environments in the Finance folder, giving each of them the same description.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; New-DbaSsisEnvironment -SqlInstance sql2019 -Folder Finance -Environment Production -WhatIf</code>
///   <para>Reports what would be created without touching the catalog.</para>
/// </example>
[Cmdlet(VerbsCommon.New, "DbaSsisEnvironment", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(PSObject))]
public sealed class NewDbaSsisEnvironmentCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The existing SSIS catalog folder to create the environments in. An environment lives in exactly one folder, so this is a single name.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public string Folder { get; set; } = null!;

    /// <summary>The name or names of the environments to create.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [Alias("Name")]
    public string[] Environment { get; set; } = null!;

    /// <summary>A description to set on each environment created by this call.</summary>
    [Parameter(Position = 4)]
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
                foreach (string environmentName in Environment)
                {
                    if (!ShouldProcess(target, $"Creating SSIS environment {environmentName} in folder {Folder}"))
                    {
                        continue;
                    }

                    try
                    {
                        CreateEnvironment(server, environmentName);
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        StopFunction($"Failure creating SSIS environment {environmentName} in folder {Folder} on {instance}", target: instance, exception: ex, continueLoop: true);
                        continue;
                    }

                    // Reading back has its own catch, and its own words. Outside one, a read-back
                    // failure - a revoked SELECT on the catalog views is enough - escaped to the
                    // per-instance handler and took every name after this one with it, which is the
                    // opposite of the independence the loop is built for. And it is not a creation
                    // failure: the environment is there, so saying so would send the caller looking
                    // for something that does not need creating.
                    try
                    {
                        EmitEnvironment(server, environmentName);
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        StopFunction($"SSIS environment {environmentName} was created in folder {Folder} on {instance} but could not be read back", target: instance, exception: ex, continueLoop: true);
                        continue;
                    }
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction($"Failure creating SSIS environments on {instance}", target: instance, exception: ex, continueLoop: true);
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
    /// The description is a parameter of the create itself, so this is one atomic call - unlike
    /// New-DbaSsisFolder, where setting a description is a second proc and can fail on its own.
    /// The two commands look symmetrical and are not.
    /// </summary>
    private void CreateEnvironment(Server server, string environmentName)
    {
        using SqlCommand command = new("EXEC [SSISDB].[catalog].[create_environment] @folder_name = @folderName, @environment_name = @environmentName, @environment_description = @environmentDescription", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", Folder);
        command.Parameters.AddWithValue("@environmentName", environmentName);
        command.Parameters.AddWithValue("@environmentDescription", (object?)Description ?? DBNull.Value);

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
    /// create_environment hands back no id, so the new environment is found by folder and name.
    /// It is re-emitted in Get-DbaSsisEnvironment's shape, decorated identically, so New -&gt; Get
    /// pipelines compose and the columns the catalog fills in itself - the creator and the
    /// creation time - are the catalog's own.
    /// </summary>
    private void EmitEnvironment(Server server, string environmentName)
    {
        using SqlCommand command = new("SELECT environments.environment_id, environments.folder_id, folders.name AS folder_name, environments.name, environments.description, environments.created_by_sid, environments.created_by_name, environments.created_time FROM [SSISDB].[catalog].[environments] environments JOIN [SSISDB].[catalog].[folders] folders ON folders.folder_id = environments.folder_id WHERE folders.name = @folderName AND environments.name = @environmentName", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", Folder);
        command.Parameters.AddWithValue("@environmentName", environmentName);

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

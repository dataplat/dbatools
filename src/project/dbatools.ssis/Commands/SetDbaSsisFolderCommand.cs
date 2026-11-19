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
/// <para type="synopsis">Changes the description or the name of an SSIS catalog folder.</para>
/// <para type="description">Sets the two things a catalog folder has: its description, through catalog.set_folder_description, and its name, through catalog.rename_folder. Those are the only folder mutators the catalog schema exposes.</para>
/// <para type="description">Takes folders either by name from -SqlInstance, or piped in from Get-DbaSsisFolder. The folder is re-read after the change and emitted in Get-DbaSsisFolder's shape, so a rename reports the new name.</para>
/// <para type="description">-NewName renames one folder. If the selection resolves to more than one folder the command changes nothing and says so, because renaming several folders to one name is an error on every folder after the first.</para>
/// <para type="description">An empty -Description is a real value: passing "" clears the description. Omitting -Description leaves it alone.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Set-DbaSsisFolder -SqlInstance sql2019 -Folder Finance -Description "Nightly finance loads"</code>
///   <para>Sets the description on the Finance folder.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Set-DbaSsisFolder -SqlInstance sql2019 -Folder Finance -Description ""</code>
///   <para>Clears the description. The empty string is the value that does it - omitting -Description would leave the old text in place.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisFolder -SqlInstance sql2019 -Folder Staging | Set-DbaSsisFolder -NewName Landing</code>
///   <para>Renames Staging to Landing and returns the folder under its new name.</para>
/// </example>
[Cmdlet(VerbsCommon.Set, "DbaSsisFolder", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(PSObject))]
public sealed partial class SetDbaSsisFolderCommand : DbaInstanceCmdlet
{
    private const string FolderTypeName = "dbatools.SsisFolder";

    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The SSIS catalog folders to change. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 2)]
    [Alias("Name")]
    public string[]? Folder { get; set; }

    /// <summary>The new description. An empty string clears it; omitting the parameter leaves the description alone.</summary>
    [Parameter(Position = 3)]
    public string? Description { get; set; }

    /// <summary>The new folder name. Renames a single folder.</summary>
    [Parameter(Position = 4)]
    public string? NewName { get; set; }

    /// <summary>SSIS catalog folder objects, typically from Get-DbaSsisFolder.</summary>
    [Parameter(ValueFromPipeline = true)]
    public PSObject[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>A folder selected for change: which server it lives on, and what it is called right now.</summary>
    private sealed class FolderTarget
    {
        internal Server Server = null!;
        internal string Name = null!;
    }

    private readonly List<FolderTarget> _renameTargets = new();
    private bool _explicitTargetsExpanded;

    protected override void BeginProcessing()
    {
        // Neither bound means the command would report success while changing nothing, which is
        // the failure mode that reads as "it worked".
        if (!TestBound(nameof(Description), nameof(NewName)))
        {
            StopFunction("You must supply -Description or -NewName; with neither there is nothing to change", category: ErrorCategory.InvalidArgument);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Duality, no parameter sets. Checked here, not in BeginProcessing, because a
        // pipeline-bound InputObject is not in BoundParameters until ProcessRecord.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        List<FolderTarget> targets = new();

        // -SqlInstance is not pipeline-bound, so it is supplied once however many records arrive.
        // Expanding it on every record instead updated the named folders once per piped object and
        // emitted each of them that many times - and under -NewName it filled the rename list with
        // repeats of one folder, which the "more than one" guard then refused.
        if (TestBound(nameof(SqlInstance)) && !_explicitTargetsExpanded)
        {
            _explicitTargetsExpanded = true;
            // -Folder selects the folders on the -SqlInstance path. Without it the selection is
            // every folder in the catalog, which is not what anyone means by "set a description".
            if (!TestBound(nameof(Folder)))
            {
                StopFunction("You must supply -Folder when connecting with -SqlInstance");
                return;
            }

            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                Server server = ResolveServer(instance);
                if (server == null)
                {
                    continue;
                }

                foreach (string name in Folder!)
                {
                    if (!FolderExists(server, name))
                    {
                        StopFunction($"SSIS folder {name} does not exist on {instance}", target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                        continue;
                    }
                    targets.Add(new FolderTarget { Server = server, Name = name });
                }
            }
        }

        foreach (PSObject piped in InputObject ?? Array.Empty<PSObject>())
        {
            if (!piped.TypeNames.Contains(FolderTypeName))
            {
                StopFunction($"Input object is not a {FolderTypeName}; pipe folders from Get-DbaSsisFolder", target: piped, category: ErrorCategory.InvalidData, continueLoop: true);
                continue;
            }

            string? instanceName = PropertyText(piped, "SqlInstance");
            string? folderName = PropertyText(piped, "Name");
            if (String.IsNullOrEmpty(instanceName) || String.IsNullOrEmpty(folderName))
            {
                StopFunction("Input object carries no SqlInstance or no folder Name", target: piped, category: ErrorCategory.InvalidData, continueLoop: true);
                continue;
            }

            Server server = ResolveServer(new DbaInstanceParameter(instanceName!));
            if (server == null)
            {
                continue;
            }

            if (!FolderExists(server, folderName!))
            {
                StopFunction($"SSIS folder {folderName} does not exist on {instanceName}", target: piped, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            targets.Add(new FolderTarget { Server = server, Name = folderName! });
        }

        // A rename is held back until the pipeline has finished feeding, because the count that
        // decides whether it is legal is the count across the whole invocation - a per-record
        // check would have renamed the first folder before the second one arrived to refuse it.
        if (TestBound(nameof(NewName)))
        {
            _renameTargets.AddRange(targets);
            return;
        }

        foreach (FolderTarget target in targets)
        {
            if (ApplyDescription(target))
            {
                EmitFolder(target.Server, target.Name);
            }
        }
    }

    protected override void EndProcessing()
    {
        if (Interrupted || !TestBound(nameof(NewName)))
        {
            return;
        }

        if (_renameTargets.Count > 1)
        {
            StringBuilder names = new();
            foreach (FolderTarget target in _renameTargets)
            {
                if (names.Length > 0)
                {
                    names.Append(", ");
                }
                names.Append(target.Name);
            }

            StopFunction($"-NewName renames one folder, and the selection resolved to {_renameTargets.Count.ToString(CultureInfo.InvariantCulture)} ({names}); nothing was changed", category: ErrorCategory.InvalidArgument);
            return;
        }

        foreach (FolderTarget target in _renameTargets)
        {
            // Both are attempted rather than short-circuited, so -WhatIf reports both actions
            // instead of reporting the description and going quiet about the rename.
            bool described = ApplyDescription(target);
            bool renamed = ApplyRename(target);
            if (described && renamed)
            {
                EmitFolder(target.Server, target.Name);
            }
        }
    }

    private Server ResolveServer(DbaInstanceParameter instance)
    {
        // The SSIS catalog schema arrived in SQL 2012, so an older instance is refused with the
        // version message rather than failing later on a missing catalog schema.
        Server server = ConnectInstance(instance, "Failure", minimumVersion: 11);
        if (server == null)
        {
            return null!;
        }

        try
        {
            // ConnectionService hands back a Server whose ConnectionContext may still be lazy;
            // SqlConnectionObject is only usable once it has actually connected.
            if (!server.ConnectionContext.IsOpen)
            {
                server.ConnectionContext.Connect();
            }

            if (!CatalogExists(server))
            {
                StopFunction($"No SSIS catalog (SSISDB) found on {instance}", target: instance, continueLoop: true);
                return null!;
            }
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            StopFunction($"Failure reaching the SSIS catalog on {instance}", target: instance, exception: ex, continueLoop: true);
            return null!;
        }

        return server;
    }

    /// <summary>
    /// Re-read rather than re-report: the caller gets what the catalog holds, which is how a
    /// rename shows the new name and how Get -&gt; Set -&gt; Get composes.
    /// </summary>
    private void EmitFolder(Server server, string folderName)
    {
        using SqlCommand command = new("SELECT folder_id, name, description, created_by_sid, created_by_name, created_time FROM [SSISDB].[catalog].[folders] WHERE name = @folderName", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", folderName);
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

    private static string? PropertyText(PSObject source, string propertyName)
    {
        PSPropertyInfo? property = source.Properties[propertyName];
        object? value = property?.Value;
        return value == null ? null : Convert.ToString(value, CultureInfo.InvariantCulture);
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

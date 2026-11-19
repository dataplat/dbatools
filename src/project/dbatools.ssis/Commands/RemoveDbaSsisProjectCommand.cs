#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// <para type="synopsis">Removes projects from the SSIS catalog.</para>
/// <para type="description">Calls catalog.delete_project for each project named or piped in. The project's pre-removal state is emitted with a Status of Dropped, decorated exactly like Get-DbaSsisProject, so a caller can log what went.</para>
/// <para type="description">It takes the version history with it. The catalog keeps up to MAX_PROJECT_VERSIONS earlier deployments of a project, and catalog.restore_project needs the project to still exist - so removing it removes the ability to go back to any of them, as well as the deployed packages themselves. Run Export-DbaSsisProject first if the .ispac is worth keeping.</para>
/// <para type="description">-Folder and -Project together are the key. Project names are unique only within a folder, so -Project on its own is ambiguous: if the name matches projects in more than one folder the command names them and removes none of them. It does not pick one and it does not remove them all.</para>
/// <para type="description">Either -Project or piped projects must be supplied. -Folder on its own still means every project in that folder, so it does not satisfy the guard - an unbounded destructive call is refused before anything connects.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Remove-DbaSsisProject -SqlInstance sql2019 -Folder Staging -Project Nightly</code>
///   <para>Removes the Nightly project from the Staging folder after confirming.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisProject -SqlInstance sql2019 -Folder Staging | Remove-DbaSsisProject -Confirm:$false</code>
///   <para>Removes every project in the Staging folder without prompting.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Remove-DbaSsisProject -SqlInstance sql2019 -Folder Staging -Project Nightly -WhatIf</code>
///   <para>Reports what would be removed and changes nothing.</para>
/// </example>
[Cmdlet(VerbsCommon.Remove, "DbaSsisProject", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed partial class RemoveDbaSsisProjectCommand : DbaInstanceCmdlet
{
    private const string ProjectTypeName = "dbatools.SsisProject";

    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The catalog folders the projects live in. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 2)]
    public string[]? Folder { get; set; }

    /// <summary>The SSIS catalog projects to remove. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 3)]
    [Alias("Name")]
    public string[]? Project { get; set; }

    /// <summary>SSIS catalog project objects, typically from Get-DbaSsisProject.</summary>
    [Parameter(ValueFromPipeline = true)]
    public PSObject[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>A project selected for removal: which server it lives on, which folder, and what it is called.</summary>
    private sealed class ProjectTarget
    {
        internal Server Server = null!;
        internal string FolderName = null!;
        internal string Name = null!;
        internal PSObject State = null!;
    }

    private bool _explicitTargetsExpanded;

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Both guards live here rather than in BeginProcessing: a pipeline-bound InputObject is not
        // in BoundParameters until ProcessRecord, so checking earlier would refuse every
        // Get-DbaSsisProject | Remove-DbaSsisProject call. A bare -SqlInstance call still reaches
        // this on its single record, which is the shape the target guard exists to refuse.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        // -Folder deliberately does not satisfy this. A folder with no project named still means
        // every project in it, which is unbounded within its scope; marking -Project mandatory
        // would close it on the surface and break -InputObject binding outright, so the
        // bound-parameter check is the guard and ConfirmImpact.High sits on top of it, not instead.
        if (!TestBound(nameof(Project), nameof(InputObject)))
        {
            StopFunction("You must supply -Project, or pipe in projects from Get-DbaSsisProject", category: ErrorCategory.InvalidArgument);
            return;
        }

        List<ProjectTarget> targets = new();

        // -SqlInstance is not pipeline-bound, so it is supplied once however many records arrive.
        if (TestBound(nameof(SqlInstance)) && !_explicitTargetsExpanded)
        {
            _explicitTargetsExpanded = true;

            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                Server server = ResolveServer(instance);
                if (server == null)
                {
                    continue;
                }

                foreach (string name in Project ?? Array.Empty<string>())
                {
                    AddResolvedTargets(targets, server, instance, name);
                }
            }
        }

        foreach (PSObject piped in InputObject ?? Array.Empty<PSObject>())
        {
            if (!piped.TypeNames.Contains(ProjectTypeName))
            {
                StopFunction($"Input object is not a {ProjectTypeName}; pipe projects from Get-DbaSsisProject", target: piped, category: ErrorCategory.InvalidData, continueLoop: true);
                continue;
            }

            string? instanceName = PropertyText(piped, "SqlInstance");
            string? folderName = PropertyText(piped, "FolderName");
            string? projectName = PropertyText(piped, "Name");
            if (String.IsNullOrEmpty(instanceName) || String.IsNullOrEmpty(folderName) || String.IsNullOrEmpty(projectName))
            {
                StopFunction("Input object carries no SqlInstance, no FolderName or no project Name", target: piped, category: ErrorCategory.InvalidData, continueLoop: true);
                continue;
            }

            Server server = ResolveServer(new DbaInstanceParameter(instanceName!));
            if (server == null)
            {
                continue;
            }

            // A piped object already names its folder, so it is never ambiguous - it is read back
            // rather than trusted, because the project may have gone since the Get- ran.
            List<PSObject> matches = ReadProjects(server, folderName, projectName!);
            if (matches.Count == 0)
            {
                StopFunction($"SSIS project {projectName} does not exist in folder {folderName} on {instanceName}", target: piped, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            targets.Add(new ProjectTarget { Server = server, FolderName = folderName!, Name = projectName!, State = matches[0] });
        }

        foreach (ProjectTarget target in targets)
        {
            if (DeleteProject(target))
            {
                // The project is gone, so the emitted object is the state captured before the call.
                target.State.Properties.Add(new PSNoteProperty("Status", "Dropped"));
                OutputHelper.SetDefaultDisplayPropertySet(target.State, "ComputerName", "InstanceName", "SqlInstance", "FolderName", "Name", "Description", "Status");
                WriteObject(target.State);
            }
        }
    }

    /// <summary>
    /// Turns one requested project name into at most one target. A name that matches in more than
    /// one folder is reported with the folders named and removed from none of them: project names
    /// are unique only within a folder, so picking one would be a guess and removing all of them
    /// would be a far bigger operation than the caller asked for.
    /// </summary>
    private void AddResolvedTargets(List<ProjectTarget> targets, Server server, DbaInstanceParameter instance, string projectName)
    {
        foreach (string? folderName in FolderScope())
        {
            List<PSObject> matches = ReadProjects(server, folderName, projectName);

            if (matches.Count == 0)
            {
                string where = folderName == null ? $"on {instance}" : $"in folder {folderName} on {instance}";
                StopFunction($"SSIS project {projectName} does not exist {where}", target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            if (matches.Count > 1)
            {
                List<string> folders = new();
                foreach (PSObject match in matches)
                {
                    folders.Add(PropertyText(match, "FolderName") ?? String.Empty);
                }
                StopFunction($"SSIS project {projectName} exists in more than one folder on {instance} ({String.Join(", ", folders)}); name the one you mean with -Folder", target: instance, category: ErrorCategory.InvalidArgument, continueLoop: true);
                continue;
            }

            targets.Add(new ProjectTarget
            {
                Server = server,
                FolderName = PropertyText(matches[0], "FolderName") ?? String.Empty,
                Name = projectName,
                State = matches[0]
            });
        }
    }

    /// <summary>
    /// The folders to look in: each one named by -Folder, or the whole catalog as a single null
    /// scope when -Folder is absent. The null is what makes the ambiguity check reachable.
    /// </summary>
    private IEnumerable<string?> FolderScope()
    {
        if (!FilterHelper.IsActive(Folder))
        {
            yield return null;
            yield break;
        }

        foreach (string folderName in Folder!)
        {
            yield return folderName;
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

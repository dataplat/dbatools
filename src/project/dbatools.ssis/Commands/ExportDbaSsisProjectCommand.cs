#nullable enable

using System;
using System.Collections.Generic;
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
/// <para type="synopsis">Writes a deployed SSIS project back out of the catalog as an .ispac file.</para>
/// <para type="description">Reads a project out of the SSIS catalog (SSISDB) with catalog.get_project and writes the .ispac the catalog holds to disk, so a deployed project can be redeployed elsewhere or kept as a build artifact. Take projects either by name from -SqlInstance, or piped in from Get-DbaSsisProject.</para>
/// <para type="description">The catalog operation is a read, but the command's effect is a file appearing on disk, so it supports -WhatIf and -Confirm and refuses to overwrite an existing file unless -Force is supplied.</para>
/// <para type="description">-Path is a directory and each project is named Folder-Project.ispac inside it; -FilePath names one file exactly. Binding both is an error, and -FilePath is refused when the selection resolves to more than one project - otherwise every project after the first would silently overwrite the previous one. With neither bound the export goes to the Path.DbatoolsExport configuration directory.</para>
/// <para type="description">Reads the catalog with parameterized T-SQL rather than the Integration Services object model, so it works on both PowerShell editions and on Linux. The catalog procedures refuse SQL Server logins, so this needs a Windows-authenticated connection.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Export-DbaSsisProject -SqlInstance sql2019 -Folder Finance -Project Ledger -Path C:\builds</code>
///   <para>Writes C:\builds\Finance-Ledger.ispac.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Export-DbaSsisProject -SqlInstance sql2019 -Folder Finance -Project Ledger -FilePath C:\builds\ledger-backup.ispac -Force</code>
///   <para>Writes that exact file, overwriting it if it is already there.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisProject -SqlInstance sql2019 -Folder Finance | Export-DbaSsisProject -Path C:\builds</code>
///   <para>Exports every project in the Finance folder, one .ispac each.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Export-DbaSsisProject -SqlInstance sql2019 -Path C:\builds | Select-Object Name, FilePath, Bytes</code>
///   <para>Exports the whole catalog and reports what landed where.</para>
/// </example>
[Cmdlet(VerbsData.Export, "DbaSsisProject", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(PSObject))]
public sealed partial class ExportDbaSsisProjectCommand : DbaInstanceCmdlet
{
    private const string ProjectTypeName = "dbatools.SsisProject";

    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials. The catalog procedures refuse SQL Server logins, so this has to be a Windows account.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Limits the export to projects in the named SSIS catalog folders. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 2)]
    public string[]? Folder { get; set; }

    /// <summary>Limits the export to the named projects. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 3)]
    [Alias("Name")]
    public string[]? Project { get; set; }

    /// <summary>The directory to write into. Each project is named Folder-Project.ispac inside it. Defaults to the Path.DbatoolsExport configuration value.</summary>
    [Parameter(Position = 4)]
    public string? Path { get; set; }

    /// <summary>The exact file to write. Only meaningful for a single project - a selection of more than one is refused rather than collapsed into one file.</summary>
    [Parameter(Position = 5)]
    public string? FilePath { get; set; }

    /// <summary>Overwrites an existing destination file. Without it an existing file is an error for that project and the rest still export.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>SSIS catalog project objects, typically from Get-DbaSsisProject.</summary>
    [Parameter(ValueFromPipeline = true)]
    public PSObject[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>A project selected for export: which server holds it, and how it is addressed there.</summary>
    private sealed class ProjectTarget
    {
        internal Server Server = null!;
        internal string FolderName = null!;
        internal string ProjectName = null!;
    }

    private readonly List<ProjectTarget> _singleFileTargets = new();
    private bool _explicitTargetsExpanded;
    private string _outputDirectory = "";

    protected override void BeginProcessing()
    {
        // A directory and a file name are two different answers to "where does this go", and
        // honouring one of them silently would put the file somewhere the caller did not ask for.
        if (TestBound(nameof(Path)) && TestBound(nameof(FilePath)))
        {
            StopFunction("-Path names a directory and -FilePath names a file; supply one or the other, not both", category: ErrorCategory.InvalidArgument);
            return;
        }

        if (!TestBound(nameof(FilePath)))
        {
            if (!TestBound(nameof(Path)))
            {
                Path = GetConfigString("Path.DbatoolsExport");
            }

            try
            {
                _outputDirectory = GetUnresolvedProviderPathFromPSPath(Path ?? String.Empty);
            }
            catch (Exception ex)
            {
                StopFunction($"Failure resolving export directory {Path}", target: Path, exception: ex);
                return;
            }

            // Checked before anything connects, and read-only: creating it here would make -WhatIf
            // leave a directory behind, so the directory is created at the point a file is written.
            if (File.Exists(_outputDirectory))
            {
                StopFunction($"Path ({_outputDirectory}) must be a directory", target: Path, category: ErrorCategory.InvalidArgument);
            }
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

        List<ProjectTarget> targets = new();

        // -SqlInstance is not pipeline-bound, so it is supplied once however many records arrive;
        // expanding it per record would export the same projects once for every piped object.
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

                List<string[]> resolved = ResolveProjects(server, Folder, Project);
                if (resolved.Count == 0)
                {
                    StopFunction($"No SSIS project matched the selection on {instance}", target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                    continue;
                }

                foreach (string[] pair in resolved)
                {
                    targets.Add(new ProjectTarget { Server = server, FolderName = pair[0], ProjectName = pair[1] });
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

            if (ResolveProjects(server, new[] { folderName! }, new[] { projectName! }).Count == 0)
            {
                StopFunction($"SSIS project {projectName} does not exist in folder {folderName} on {instanceName}", target: piped, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            targets.Add(new ProjectTarget { Server = server, FolderName = folderName!, ProjectName = projectName! });
        }

        // -FilePath is held back until the pipeline has finished feeding, because the count that
        // decides whether it is legal is the count across the whole invocation - a per-record check
        // would have written the first project to the file before the second arrived to refuse it,
        // and the caller would be holding one file believing they had several.
        if (TestBound(nameof(FilePath)))
        {
            _singleFileTargets.AddRange(targets);
            return;
        }

        foreach (ProjectTarget target in targets)
        {
            ExportProject(target);
        }
    }

    protected override void EndProcessing()
    {
        if (Interrupted || !TestBound(nameof(FilePath)))
        {
            return;
        }

        if (_singleFileTargets.Count > 1)
        {
            StringBuilder names = new();
            foreach (ProjectTarget target in _singleFileTargets)
            {
                if (names.Length > 0)
                {
                    names.Append(", ");
                }
                names.Append(target.FolderName).Append('\\').Append(target.ProjectName);
            }

            StopFunction($"-FilePath writes one project, and the selection resolved to {_singleFileTargets.Count.ToString(CultureInfo.InvariantCulture)} ({names}); nothing was exported - use -Path to export them all", category: ErrorCategory.InvalidArgument);
            return;
        }

        foreach (ProjectTarget target in _singleFileTargets)
        {
            ExportProject(target);
        }
    }

    private void ExportProject(ProjectTarget target)
    {
        string instance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(target.Server);

        string destination;
        try
        {
            destination = TestBound(nameof(FilePath))
                ? GetUnresolvedProviderPathFromPSPath(FilePath ?? String.Empty)
                : System.IO.Path.Combine(_outputDirectory, $"{target.FolderName}-{target.ProjectName}.ispac");
        }
        catch (Exception ex)
        {
            StopFunction($"Failure resolving the export path for SSIS project {target.ProjectName}", target: target.ProjectName, exception: ex, continueLoop: true);
            return;
        }

        // Checked before the catalog read so an accidental re-run costs nothing, and refused per
        // project so one existing file does not abandon the rest of the selection.
        if (File.Exists(destination) && !Force.ToBool())
        {
            StopFunction($"{destination} already exists; use -Force to overwrite it", target: destination, category: ErrorCategory.ResourceExists, continueLoop: true);
            return;
        }

        if (!ShouldProcess(instance, $"Exporting SSIS project {target.ProjectName} from folder {target.FolderName} to {destination}"))
        {
            return;
        }

        byte[] projectStream;
        try
        {
            byte[]? read = ReadProjectStream(target);
            // The catalog raises for a project it cannot find, so an empty answer means it found
            // one and had nothing to hand back. Writing that would leave a zero-byte .ispac that
            // reads as a successful export right up until someone tries to deploy it.
            if (read == null || read.Length == 0)
            {
                StopFunction($"The SSIS catalog on {instance} returned no project stream for {target.ProjectName} in folder {target.FolderName}; nothing was written", target: target.ProjectName, category: ErrorCategory.InvalidResult, continueLoop: true);
                return;
            }
            projectStream = read;
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            StopFunction($"Failure reading SSIS project {target.ProjectName} in folder {target.FolderName} from {instance}", target: target.ProjectName, exception: ex, continueLoop: true);
            return;
        }

        try
        {
            string? parent = System.IO.Path.GetDirectoryName(destination);
            if (!String.IsNullOrEmpty(parent) && !Directory.Exists(parent))
            {
                Directory.CreateDirectory(parent!);
            }
            File.WriteAllBytes(destination, projectStream);
        }
        catch (Exception ex)
        {
            StopFunction($"Failure writing SSIS project {target.ProjectName} to {destination}", target: destination, exception: ex, continueLoop: true);
            return;
        }

        EmitProject(target, destination, projectStream.LongLength);
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

    private string? GetConfigString(string key)
    {
        object? raw = Dataplat.Dbatools.Connection.ConnectionService.GetConfigurationValue(key);
        return raw == null
            ? null
            : (string)LanguagePrimitives.ConvertTo(raw, typeof(string), CultureInfo.InvariantCulture);
    }
}

#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// <para type="synopsis">Changes the description, the name or the folder of an SSIS catalog environment.</para>
/// <para type="description">Sets the three things the catalog lets you change about an environment: its description, through catalog.set_environment_property, its name, through catalog.rename_environment, and which folder it lives in, through catalog.move_environment.</para>
/// <para type="description">Takes environments either by name from -SqlInstance, or piped in from Get-DbaSsisEnvironment. The environment is re-read after all three operations and emitted in Get-DbaSsisEnvironment's shape, so a rename plus a move reports the final name and the final folder.</para>
/// <para type="description">-NewName and -MoveToFolder each act on one environment. If the selection resolves to more than one the command changes nothing and says so, because renaming several environments to one name - or the second move into a folder that already has the moved name - is an error on everything after the first.</para>
/// <para type="description">An empty -Description is a real value: passing "" clears the description. Omitting -Description leaves it alone.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Set-DbaSsisEnvironment -SqlInstance sql2019 -Folder Finance -Environment Production -Description "Live connection managers"</code>
///   <para>Sets the description on the Production environment in the Finance folder.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Set-DbaSsisEnvironment -SqlInstance sql2019 -Folder Finance -Environment Production -Description ""</code>
///   <para>Clears the description. The empty string is the value that does it - omitting -Description would leave the old text in place.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisEnvironment -SqlInstance sql2019 -Folder Staging -Environment Test | Set-DbaSsisEnvironment -NewName QA -MoveToFolder Finance</code>
///   <para>Renames Test to QA and then moves it from Staging to Finance, returning the environment under its new name in its new folder.</para>
/// </example>
[Cmdlet(VerbsCommon.Set, "DbaSsisEnvironment", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(PSObject))]
public sealed partial class SetDbaSsisEnvironmentCommand : DbaInstanceCmdlet
{
    private const string EnvironmentTypeName = "dbatools.SsisEnvironment";

    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The folders the environments live in now. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 2)]
    public string[]? Folder { get; set; }

    /// <summary>The SSIS catalog environments to change. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 3)]
    [Alias("Name")]
    public string[]? Environment { get; set; }

    /// <summary>The new description. An empty string clears it; omitting the parameter leaves the description alone.</summary>
    [Parameter(Position = 4)]
    public string? Description { get; set; }

    /// <summary>The new environment name. Renames a single environment.</summary>
    [Parameter(Position = 5)]
    public string? NewName { get; set; }

    /// <summary>The folder to move the environment into. Moves a single environment, and it happens after the description and the rename.</summary>
    [Parameter(Position = 6)]
    public string? MoveToFolder { get; set; }

    /// <summary>SSIS catalog environment objects, typically from Get-DbaSsisEnvironment.</summary>
    [Parameter(ValueFromPipeline = true)]
    public PSObject[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>An environment selected for change: which server it is on, and where it sits right now.</summary>
    private sealed class EnvironmentTarget
    {
        internal Server Server = null!;
        internal string FolderName = null!;
        internal string Name = null!;
    }

    private readonly List<EnvironmentTarget> _singularTargets = new();
    private bool _explicitTargetsExpanded;

    /// <summary>Whether this invocation carries a change that only makes sense against one environment.</summary>
    private bool SingularChangeRequested => TestBound(nameof(NewName)) || TestBound(nameof(MoveToFolder));

    protected override void BeginProcessing()
    {
        // None of the three bound means the command would report success while changing nothing,
        // which is the failure mode that reads as "it worked".
        if (!TestBound(nameof(Description), nameof(NewName), nameof(MoveToFolder)))
        {
            StopFunction("You must supply -Description, -NewName or -MoveToFolder; with none of them there is nothing to change", category: ErrorCategory.InvalidArgument);
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

        List<EnvironmentTarget> targets = new();

        // -SqlInstance is not pipeline-bound, so it is supplied once however many records arrive.
        // Expanding it per record would apply the change once per piped object and emit each
        // environment that many times.
        if (TestBound(nameof(SqlInstance)) && !_explicitTargetsExpanded)
        {
            _explicitTargetsExpanded = true;
            // With neither selector the selection is every environment in the catalog, which is
            // not what anyone means by "set a description".
            if (!TestBound(nameof(Folder), nameof(Environment)))
            {
                StopFunction("You must supply -Folder or -Environment when connecting with -SqlInstance");
                return;
            }

            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                Server server = ResolveServer(instance);
                if (server == null)
                {
                    continue;
                }

                List<string[]> resolved = ResolveEnvironments(server, Folder, Environment);
                foreach (string[] row in resolved)
                {
                    targets.Add(new EnvironmentTarget { Server = server, FolderName = row[0], Name = row[1] });
                }

                // A name the caller typed that matched nothing is reported as missing rather than
                // silently dropped - the count of things changed would otherwise be the only clue.
                ReportUnmatchedNames(instance, resolved);
            }
        }

        foreach (PSObject piped in InputObject ?? Array.Empty<PSObject>())
        {
            if (!piped.TypeNames.Contains(EnvironmentTypeName))
            {
                StopFunction($"Input object is not a {EnvironmentTypeName}; pipe environments from Get-DbaSsisEnvironment", target: piped, category: ErrorCategory.InvalidData, continueLoop: true);
                continue;
            }

            string? instanceName = PropertyText(piped, "SqlInstance");
            string? folderName = PropertyText(piped, "FolderName");
            string? environmentName = PropertyText(piped, "Name");
            if (String.IsNullOrEmpty(instanceName) || String.IsNullOrEmpty(folderName) || String.IsNullOrEmpty(environmentName))
            {
                StopFunction("Input object carries no SqlInstance, no FolderName or no environment Name", target: piped, category: ErrorCategory.InvalidData, continueLoop: true);
                continue;
            }

            Server server = ResolveServer(new DbaInstanceParameter(instanceName!));
            if (server == null)
            {
                continue;
            }

            if (!EnvironmentExists(server, folderName!, environmentName!))
            {
                StopFunction($"SSIS environment {environmentName} does not exist in folder {folderName} on {instanceName}", target: piped, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            targets.Add(new EnvironmentTarget { Server = server, FolderName = folderName!, Name = environmentName! });
        }

        // A rename or a move is held back until the pipeline has finished feeding, because the
        // count that decides whether it is legal is the count across the whole invocation - a
        // per-record check would have renamed the first environment before the second one arrived
        // to refuse it.
        if (SingularChangeRequested)
        {
            _singularTargets.AddRange(targets);
            return;
        }

        foreach (EnvironmentTarget target in targets)
        {
            if (ApplyDescription(target))
            {
                EmitEnvironment(target);
            }
        }
    }

    protected override void EndProcessing()
    {
        if (Interrupted || !SingularChangeRequested)
        {
            return;
        }

        if (_singularTargets.Count > 1)
        {
            StringBuilder names = new();
            foreach (EnvironmentTarget target in _singularTargets)
            {
                if (names.Length > 0)
                {
                    names.Append(", ");
                }
                names.Append(target.FolderName).Append('\\').Append(target.Name);
            }

            StopFunction($"{SingularParameterLabel()} one environment, and the selection resolved to {_singularTargets.Count.ToString(CultureInfo.InvariantCulture)} ({names}); nothing was changed", category: ErrorCategory.InvalidArgument);
            return;
        }

        foreach (EnvironmentTarget target in _singularTargets)
        {
            // All three are attempted rather than short-circuited, so -WhatIf reports every action
            // instead of reporting the description and going quiet about the rename and the move.
            bool described = ApplyDescription(target);
            bool renamed = ApplyRename(target);
            // The move goes last so the description and the rename still address the environment
            // where it was resolved; moving first would invalidate the folder they were bound to.
            bool moved = ApplyMove(target);
            if (described && renamed && moved)
            {
                EmitEnvironment(target);
            }
        }
    }

    private string SingularParameterLabel()
    {
        if (TestBound(nameof(NewName)) && TestBound(nameof(MoveToFolder)))
        {
            return "-NewName and -MoveToFolder each act on";
        }
        return TestBound(nameof(NewName)) ? "-NewName renames" : "-MoveToFolder moves";
    }

    /// <summary>
    /// Reports the names the catalog had nothing for. -Folder is only reported on when it is the
    /// sole selector: alongside -Environment it is a scope rather than an ask, and a folder that
    /// holds environments other than the named ones is not a missing folder.
    /// </summary>
    private void ReportUnmatchedNames(DbaInstanceParameter instance, List<string[]> resolved)
    {
        if (FilterHelper.IsActive(Folder) && !FilterHelper.IsActive(Environment))
        {
            foreach (string folderName in Folder!)
            {
                if (!resolved.Exists(row => String.Equals(row[0], folderName, StringComparison.OrdinalIgnoreCase)))
                {
                    StopFunction($"No SSIS environment found in folder {folderName} on {instance}", target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                }
            }
        }

        if (FilterHelper.IsActive(Environment))
        {
            foreach (string environmentName in Environment!)
            {
                if (!resolved.Exists(row => String.Equals(row[1], environmentName, StringComparison.OrdinalIgnoreCase)))
                {
                    string scope = FilterHelper.IsActive(Folder) ? $" in {String.Join(", ", Folder!)}" : String.Empty;
                    StopFunction($"SSIS environment {environmentName} does not exist{scope} on {instance}", target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                }
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

    private static string? PropertyText(PSObject source, string propertyName)
    {
        PSPropertyInfo? property = source.Properties[propertyName];
        object? value = property?.Value;
        return value == null ? null : Convert.ToString(value, CultureInfo.InvariantCulture);
    }
}

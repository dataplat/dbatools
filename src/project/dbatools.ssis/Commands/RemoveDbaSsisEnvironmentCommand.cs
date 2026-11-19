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
/// <para type="synopsis">Removes environments from the SSIS catalog.</para>
/// <para type="description">Calls catalog.delete_environment for each environment named or piped in. The environment's pre-removal state is emitted with a Status of Dropped, decorated exactly like Get-DbaSsisEnvironment, so a caller can log what went.</para>
/// <para type="description">It takes every variable in the environment with it, including the sensitive ones. Sensitive values are stored encrypted and there is no export path for them - Get-DbaSsisEnvironmentVariable cannot return a plaintext sensitive value - so an environment full of passwords cannot be rebuilt from anything dbatools can read.</para>
/// <para type="description">It also breaks any project bound to it. catalog.environment_references ties projects to environments, and an execution created against a removed environment's reference cannot resolve. Check catalog.environment_references before removing an environment a project may still point at.</para>
/// <para type="description">-Folder and -Environment together are the key. Environment names are unique only within a folder, so -Environment on its own is ambiguous: if the name matches environments in more than one folder the command names them and removes none of them.</para>
/// <para type="description">Either -Environment or piped environments must be supplied. -Folder on its own still means every environment in that folder, so it does not satisfy the guard - an unbounded destructive call is refused before anything connects.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Remove-DbaSsisEnvironment -SqlInstance sql2019 -Folder Finance -Environment Production</code>
///   <para>Removes the Production environment from the Finance folder after confirming.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisEnvironment -SqlInstance sql2019 -Folder Finance | Remove-DbaSsisEnvironment -Confirm:$false</code>
///   <para>Removes every environment in the Finance folder without prompting.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Remove-DbaSsisEnvironment -SqlInstance sql2019 -Folder Finance -Environment Production -WhatIf</code>
///   <para>Reports what would be removed and changes nothing.</para>
/// </example>
[Cmdlet(VerbsCommon.Remove, "DbaSsisEnvironment", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed partial class RemoveDbaSsisEnvironmentCommand : DbaInstanceCmdlet
{
    private const string EnvironmentTypeName = "dbatools.SsisEnvironment";

    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The catalog folders the environments live in. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 2)]
    public string[]? Folder { get; set; }

    /// <summary>The SSIS catalog environments to remove. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 3)]
    [Alias("Name")]
    public string[]? Environment { get; set; }

    /// <summary>SSIS catalog environment objects, typically from Get-DbaSsisEnvironment.</summary>
    [Parameter(ValueFromPipeline = true)]
    public PSObject[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>An environment selected for removal: which server it lives on, which folder, and what it is called.</summary>
    private sealed class EnvironmentTarget
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
        // Get-DbaSsisEnvironment | Remove-DbaSsisEnvironment call. A bare -SqlInstance call still
        // reaches this on its single record, which is the shape the target guard exists to refuse.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        // -Folder deliberately does not satisfy this. A folder with no environment named still
        // means every environment in it, which is unbounded within its scope; marking -Environment
        // mandatory would close it on the surface and break -InputObject binding outright, so the
        // bound-parameter check is the guard and ConfirmImpact.High sits on top of it, not instead.
        if (!TestBound(nameof(Environment), nameof(InputObject)))
        {
            StopFunction("You must supply -Environment, or pipe in environments from Get-DbaSsisEnvironment", category: ErrorCategory.InvalidArgument);
            return;
        }

        List<EnvironmentTarget> targets = new();

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

                foreach (string name in Environment ?? Array.Empty<string>())
                {
                    AddResolvedTargets(targets, server, instance, name);
                }
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

            // A piped object already names its folder, so it is never ambiguous - it is read back
            // rather than trusted, because the environment may have gone since the Get- ran.
            List<PSObject> matches = ReadEnvironments(server, folderName, environmentName!);
            if (matches.Count == 0)
            {
                StopFunction($"SSIS environment {environmentName} does not exist in folder {folderName} on {instanceName}", target: piped, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            targets.Add(new EnvironmentTarget { Server = server, FolderName = folderName!, Name = environmentName!, State = matches[0] });
        }

        foreach (EnvironmentTarget target in targets)
        {
            if (DeleteEnvironment(target))
            {
                // The environment is gone, so the emitted object is the state captured before the call.
                target.State.Properties.Add(new PSNoteProperty("Status", "Dropped"));
                OutputHelper.SetDefaultDisplayPropertySet(target.State, "ComputerName", "InstanceName", "SqlInstance", "FolderName", "Name", "Description", "Status");
                WriteObject(target.State);
            }
        }
    }

    /// <summary>
    /// Turns one requested environment name into at most one target. A name that matches in more
    /// than one folder is reported with the folders named and removed from none of them:
    /// environment names are unique only within a folder, so picking one would be a guess and
    /// removing all of them would be a far bigger operation than the caller asked for.
    /// </summary>
    private void AddResolvedTargets(List<EnvironmentTarget> targets, Server server, DbaInstanceParameter instance, string environmentName)
    {
        foreach (string? folderName in FolderScope())
        {
            List<PSObject> matches = ReadEnvironments(server, folderName, environmentName);

            if (matches.Count == 0)
            {
                string where = folderName == null ? $"on {instance}" : $"in folder {folderName} on {instance}";
                StopFunction($"SSIS environment {environmentName} does not exist {where}", target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            if (matches.Count > 1)
            {
                List<string> folders = new();
                foreach (PSObject match in matches)
                {
                    folders.Add(PropertyText(match, "FolderName") ?? String.Empty);
                }
                StopFunction($"SSIS environment {environmentName} exists in more than one folder on {instance} ({String.Join(", ", folders)}); name the one you mean with -Folder", target: instance, category: ErrorCategory.InvalidArgument, continueLoop: true);
                continue;
            }

            targets.Add(new EnvironmentTarget
            {
                Server = server,
                FolderName = PropertyText(matches[0], "FolderName") ?? String.Empty,
                Name = environmentName,
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

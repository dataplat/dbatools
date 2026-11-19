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
/// <para type="synopsis">Removes variables from an SSIS catalog environment.</para>
/// <para type="description">Calls catalog.delete_environment_variable for each variable named or piped in. The variable's pre-removal state is emitted with a Status of Dropped, in the same shape Get-DbaSsisEnvironmentVariable and New-DbaSsisEnvironmentVariable use, so a caller can log what went.</para>
/// <para type="description">A sensitive variable cannot be rebuilt from anything dbatools can read. Its value is stored encrypted and no read path in the module returns the plaintext, so removing it destroys the only copy the catalog had - which is why a single-row delete carries ConfirmImpact High. The value is never echoed on the way out, sensitive or not.</para>
/// <para type="description">The full key is folder plus environment plus variable. Variable names are unique only within an environment and environment names only within a folder, so a partial key resolves across the catalog: if the name matches variables in more than one environment the command names them and removes none of them.</para>
/// <para type="description">Either -Variable or piped variables must be supplied. Neither -Folder nor -Environment satisfies the guard - an environment with no variable named still means every variable in it, which empties it - so an unbounded destructive call is refused before anything connects.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Remove-DbaSsisEnvironmentVariable -SqlInstance sql2019 -Folder Finance -Environment Production -Variable BatchSize</code>
///   <para>Removes the BatchSize variable from the Production environment after confirming.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisEnvironmentVariable -SqlInstance sql2019 -Folder Finance -Environment Production | Remove-DbaSsisEnvironmentVariable -Confirm:$false</code>
///   <para>Empties the Production environment without prompting. Get-DbaSsisEnvironmentVariable goes through the Integration Services object model, so this form is Windows PowerShell only; the -Variable form works on both editions.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Remove-DbaSsisEnvironmentVariable -SqlInstance sql2019 -Folder Finance -Environment Production -Variable ApiKey -WhatIf</code>
///   <para>Reports what would be removed and changes nothing.</para>
/// </example>
[Cmdlet(VerbsCommon.Remove, "DbaSsisEnvironmentVariable", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed partial class RemoveDbaSsisEnvironmentVariableCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The catalog folders the environments live in. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 2)]
    public string[]? Folder { get; set; }

    /// <summary>The environments the variables live in. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 3)]
    public string[]? Environment { get; set; }

    /// <summary>The environment variables to remove. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 4)]
    [Alias("Name")]
    public string[]? Variable { get; set; }

    /// <summary>SSIS catalog environment variable objects, typically from Get-DbaSsisEnvironmentVariable or New-DbaSsisEnvironmentVariable.</summary>
    [Parameter(ValueFromPipeline = true)]
    public PSObject[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>A variable selected for removal, addressed by the full three-part catalog key.</summary>
    private sealed class VariableTarget
    {
        internal Server Server = null!;
        internal string FolderName = null!;
        internal string EnvironmentName = null!;
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
        // Get-DbaSsisEnvironmentVariable | Remove-DbaSsisEnvironmentVariable call. A bare
        // -SqlInstance call still reaches this on its single record, which is the shape the target
        // guard exists to refuse.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        // Neither -Folder nor -Environment satisfies this. An environment with no variable named
        // still means every variable in it, which empties it; marking -Variable mandatory would
        // close it on the surface and break -InputObject binding outright, so the bound-parameter
        // check is the guard and ConfirmImpact.High sits on top of it, not instead.
        if (!TestBound(nameof(Variable), nameof(InputObject)))
        {
            StopFunction("You must supply -Variable, or pipe in variables from Get-DbaSsisEnvironmentVariable", category: ErrorCategory.InvalidArgument);
            return;
        }

        List<VariableTarget> targets = new();

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

                foreach (string name in Variable ?? Array.Empty<string>())
                {
                    AddResolvedTargets(targets, server, instance, name);
                }
            }
        }

        foreach (PSObject piped in InputObject ?? Array.Empty<PSObject>())
        {
            // Carriage, not a type name: the whole variable family - Get-, New- and Set- - emits a
            // decorated PSObject with no dbatools.Ssis* type name on it, so a type-name check here
            // would refuse the one composition the help documents.
            string? instanceName = PropertyText(piped, "SqlInstance");
            string? folderName = PropertyText(piped, "Folder");
            string? environmentName = PropertyText(piped, "Environment");
            string? variableName = PropertyText(piped, "Name");
            if (String.IsNullOrEmpty(instanceName) || String.IsNullOrEmpty(folderName) || String.IsNullOrEmpty(environmentName) || String.IsNullOrEmpty(variableName))
            {
                StopFunction("Input object is not an SSIS environment variable; it must carry SqlInstance, Folder, Environment and Name", target: piped, category: ErrorCategory.InvalidData, continueLoop: true);
                continue;
            }

            Server server = ResolveServer(new DbaInstanceParameter(instanceName!));
            if (server == null)
            {
                continue;
            }

            // A piped object already carries the full key, so it is never ambiguous - it is read
            // back rather than trusted, because the variable may have gone since the Get- ran.
            List<PSObject> matches = ReadVariables(server, folderName, environmentName, variableName!);
            if (matches.Count == 0)
            {
                StopFunction($"SSIS environment variable {variableName} does not exist in {folderName}\\{environmentName} on {instanceName}", target: piped, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            targets.Add(new VariableTarget
            {
                Server = server,
                FolderName = folderName!,
                EnvironmentName = environmentName!,
                Name = variableName!,
                State = matches[0]
            });
        }

        foreach (VariableTarget target in targets)
        {
            if (DeleteVariable(target))
            {
                // The variable is gone, so the emitted object is the state captured before the call.
                target.State.Properties.Add(new PSNoteProperty("Status", "Dropped"));
                WriteObject(target.State);
            }
        }
    }

    /// <summary>
    /// Turns one requested variable name into at most one target. A name that matches in more than
    /// one folder or environment is reported with the matches named and removed from none of them:
    /// the catalog key is folder plus environment plus variable, so picking one would be a guess
    /// and removing all of them would be a far bigger operation than the caller asked for.
    /// </summary>
    private void AddResolvedTargets(List<VariableTarget> targets, Server server, DbaInstanceParameter instance, string variableName)
    {
        foreach (string? folderName in NameScope(Folder))
        {
            foreach (string? environmentName in NameScope(Environment))
            {
                List<PSObject> matches = ReadVariables(server, folderName, environmentName, variableName);

                if (matches.Count == 0)
                {
                    StopFunction($"SSIS environment variable {variableName} does not exist {DescribeScope(folderName, environmentName, instance)}", target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                    continue;
                }

                if (matches.Count > 1)
                {
                    List<string> found = new();
                    foreach (PSObject match in matches)
                    {
                        found.Add($"{PropertyText(match, "Folder")}\\{PropertyText(match, "Environment")}");
                    }
                    StopFunction($"SSIS environment variable {variableName} exists in more than one environment on {instance} ({String.Join(", ", found)}); name the one you mean with -Folder and -Environment", target: instance, category: ErrorCategory.InvalidArgument, continueLoop: true);
                    continue;
                }

                targets.Add(new VariableTarget
                {
                    Server = server,
                    FolderName = PropertyText(matches[0], "Folder") ?? String.Empty,
                    EnvironmentName = PropertyText(matches[0], "Environment") ?? String.Empty,
                    Name = variableName,
                    State = matches[0]
                });
            }
        }
    }

    private static string DescribeScope(string? folderName, string? environmentName, DbaInstanceParameter instance)
    {
        if (folderName == null && environmentName == null)
        {
            return $"on {instance}";
        }
        if (folderName == null)
        {
            return $"in environment {environmentName} on {instance}";
        }
        if (environmentName == null)
        {
            return $"in folder {folderName} on {instance}";
        }
        return $"in {folderName}\\{environmentName} on {instance}";
    }

    /// <summary>
    /// The names to look under: each one supplied, or the whole catalog as a single null scope when
    /// the parameter is absent. The null is what makes the ambiguity check reachable.
    /// </summary>
    private static IEnumerable<string?> NameScope(string[]? names)
    {
        if (!FilterHelper.IsActive(names))
        {
            yield return null;
            yield break;
        }

        foreach (string name in names!)
        {
            yield return name;
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

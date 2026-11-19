#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// <para type="synopsis">Removes folders from the SSIS catalog.</para>
/// <para type="description">Calls catalog.delete_folder for each folder named or piped in. The folder's pre-removal state is emitted with a Status of Dropped, decorated exactly like Get-DbaSsisFolder, so a caller can log what went.</para>
/// <para type="description">A folder is a container - projects and environments live inside it - so this is not a leaf delete. What the catalog does with a folder that still holds objects is the server's decision, not this command's: the proc is called and its error is surfaced verbatim rather than pre-flighting a count and inventing a rule that could disagree with the server. On SQL 2019 (catalog SCHEMA_VERSION 6) a non-empty folder is refused with "Only empty folders can be deleted".</para>
/// <para type="description">Either -Folder or piped folders must be supplied. -SqlInstance on its own would mean every folder in the catalog, and an unbounded destructive call with no explicit target is refused before anything connects.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Remove-DbaSsisFolder -SqlInstance sql2019 -Folder Staging</code>
///   <para>Removes the Staging folder after confirming.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisFolder -SqlInstance sql2019 -Folder Staging, Landing | Remove-DbaSsisFolder -Confirm:$false</code>
///   <para>Removes both folders without prompting.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Remove-DbaSsisFolder -SqlInstance sql2019 -Folder Staging -WhatIf</code>
///   <para>Reports what would be removed and changes nothing.</para>
/// </example>
[Cmdlet(VerbsCommon.Remove, "DbaSsisFolder", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed partial class RemoveDbaSsisFolderCommand : DbaInstanceCmdlet
{
    private const string FolderTypeName = "dbatools.SsisFolder";

    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The SSIS catalog folders to remove. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 2)]
    [Alias("Name")]
    public string[]? Folder { get; set; }

    /// <summary>SSIS catalog folder objects, typically from Get-DbaSsisFolder.</summary>
    [Parameter(ValueFromPipeline = true)]
    public PSObject[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>A folder selected for removal: which server it lives on, and what it is called.</summary>
    private sealed class FolderTarget
    {
        internal Server Server = null!;
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
        // Get-DbaSsisFolder | Remove-DbaSsisFolder call. A bare -SqlInstance call still reaches this
        // on its single record, which is the shape the target guard exists to refuse.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        // Without a named target the selection is every folder in the catalog. Marking -Folder
        // mandatory would close it on the surface and break -InputObject binding outright, so the
        // bound-parameter check is the guard and ConfirmImpact.High sits on top of it, not instead.
        if (!TestBound(nameof(Folder), nameof(InputObject)))
        {
            StopFunction("You must supply -Folder, or pipe in folders from Get-DbaSsisFolder", category: ErrorCategory.InvalidArgument);
            return;
        }

        List<FolderTarget> targets = new();

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

                foreach (string name in Folder ?? Array.Empty<string>())
                {
                    PSObject? state = ReadFolder(server, name);
                    if (state == null)
                    {
                        StopFunction($"SSIS folder {name} does not exist on {instance}", target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                        continue;
                    }
                    targets.Add(new FolderTarget { Server = server, Name = name, State = state });
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

            PSObject? state = ReadFolder(server, folderName!);
            if (state == null)
            {
                StopFunction($"SSIS folder {folderName} does not exist on {instanceName}", target: piped, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            targets.Add(new FolderTarget { Server = server, Name = folderName!, State = state });
        }

        foreach (FolderTarget target in targets)
        {
            if (DeleteFolder(target))
            {
                // The folder is gone, so the emitted object is the state captured before the call.
                target.State.Properties.Add(new PSNoteProperty("Status", "Dropped"));
                OutputHelper.SetDefaultDisplayPropertySet(target.State, "ComputerName", "InstanceName", "SqlInstance", "Name", "Description", "Status");
                WriteObject(target.State);
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

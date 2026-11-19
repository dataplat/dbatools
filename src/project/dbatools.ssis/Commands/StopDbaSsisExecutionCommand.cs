#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// <para type="synopsis">Stops running SSIS catalog executions.</para>
/// <para type="description">Calls catalog.stop_operation for each execution named or piped in, then re-reads the execution and emits it decorated exactly like Get-DbaSsisExecution.</para>
/// <para type="description">The stop is a request, not a completed cancellation. The catalog marks the execution Stopping and asks the running package to come down, so the status this command returns is very often Stopping rather than Cancelled. Re-read with Get-DbaSsisExecution rather than treating the returned status as final.</para>
/// <para type="description">Killing a running package aborts an ETL mid-flight, and what a half-run package leaves behind depends entirely on that package's own transaction handling - dbatools cannot roll it back. That is the ConfirmImpact High argument.</para>
/// <para type="description">Only a Running execution can be stopped. The catalog's own predicate is the reason: internal.prepare_stop matches the operation only while its status is Running or Stopping, and refuses a Stopping one outright. An execution in any other status is reported by name and skipped without a stop being issued - including one that finished between the Get- and the Stop-, which is a race no caller can avoid and not worth failing over.</para>
/// <para type="description">Either -ExecutionId or piped executions must be supplied. A bare -SqlInstance would mean every running execution on the server, so it is refused before anything connects.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Stop-DbaSsisExecution -SqlInstance sql2019 -ExecutionId 1234</code>
///   <para>Asks the catalog to stop execution 1234 after confirming.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisExecution -SqlInstance sql2019 -Status Running | Stop-DbaSsisExecution -Confirm:$false</code>
///   <para>Stops every execution currently running on the instance without prompting.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Stop-DbaSsisExecution -SqlInstance sql2019 -ExecutionId 1234 -WhatIf</code>
///   <para>Reports what would be stopped and leaves the execution running.</para>
/// </example>
[Cmdlet(VerbsLifecycle.Stop, "DbaSsisExecution", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed partial class StopDbaSsisExecutionCommand : DbaInstanceCmdlet
{
    private const string ExecutionTypeName = "dbatools.SsisExecution";

    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The executions to stop. catalog.executions.execution_id is a bigint, so this is Int64 - an Int32 here would overflow on a long-lived catalog.</summary>
    [Parameter(Position = 2)]
    public long[]? ExecutionId { get; set; }

    /// <summary>SSIS catalog execution objects, typically from Get-DbaSsisExecution.</summary>
    [Parameter(ValueFromPipeline = true)]
    public PSObject[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>An execution selected to be stopped: which server it is on, and which id.</summary>
    private sealed class ExecutionTarget
    {
        internal Server Server = null!;
        internal long Id;
        internal object? Target;
    }

    private bool _explicitTargetsExpanded;

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Both guards live here rather than in BeginProcessing: a pipeline-bound InputObject is not
        // in BoundParameters until ProcessRecord, so checking earlier would refuse the
        // Get-DbaSsisExecution -Status Running | Stop-DbaSsisExecution call the command exists for.
        // A bare -SqlInstance call still reaches this on its single record, which is the shape the
        // target guard exists to refuse.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        // An instance with no execution named means every running execution on it. Marking
        // -ExecutionId mandatory would close that on the surface and break -InputObject binding
        // outright, so the bound-parameter check is the guard and ConfirmImpact.High sits on top of
        // it, not instead.
        if (!TestBound(nameof(ExecutionId), nameof(InputObject)))
        {
            StopFunction("You must supply -ExecutionId, or pipe in executions from Get-DbaSsisExecution", category: ErrorCategory.InvalidArgument);
            return;
        }

        List<ExecutionTarget> targets = new();

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

                foreach (long id in ExecutionId ?? Array.Empty<long>())
                {
                    targets.Add(new ExecutionTarget { Server = server, Id = id, Target = instance });
                }
            }
        }

        foreach (PSObject piped in InputObject ?? Array.Empty<PSObject>())
        {
            if (!piped.TypeNames.Contains(ExecutionTypeName))
            {
                StopFunction($"Input object is not a {ExecutionTypeName}; pipe executions from Get-DbaSsisExecution", target: piped, category: ErrorCategory.InvalidData, continueLoop: true);
                continue;
            }

            string? instanceName = PropertyText(piped, "SqlInstance");
            string? executionId = PropertyText(piped, "ExecutionID");
            if (String.IsNullOrEmpty(instanceName) || String.IsNullOrEmpty(executionId) || !Int64.TryParse(executionId, NumberStyles.Integer, CultureInfo.InvariantCulture, out long parsedId))
            {
                StopFunction("Input object carries no SqlInstance or no ExecutionID", target: piped, category: ErrorCategory.InvalidData, continueLoop: true);
                continue;
            }

            Server server = ResolveServer(new DbaInstanceParameter(instanceName!));
            if (server == null)
            {
                continue;
            }

            targets.Add(new ExecutionTarget { Server = server, Id = parsedId, Target = piped });
        }

        foreach (ExecutionTarget target in targets)
        {
            StopExecution(target);
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

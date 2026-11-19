#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Lists waiting tasks. Port of public/Get-DbaWaitingTask.ps1 (W1-103). The begin block
/// interpolates the is_user_process predicate from Test-Bound IncludeSystemSpid (an
/// explicit :$false still selects the system branch); the un-tried $server.Query keeps a
/// STALE function-scope $results on fault; each instance rides one VERBATIM hop (the row
/// loop with the Test-Bound-gated -notin Spid filter and its contained continue, the
/// 16-prop PSCustomObject whose InfoUrl reads a column the query aliases as [URL] - a
/// missing DataRow read is a silent null, bug preserved - and the Select-DefaultView
/// exclude triple). Surface pinned by migration/baselines/Get-DbaWaitingTask.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaWaitingTask")]
public sealed class GetDbaWaitingTaskCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The session id(s) to include.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 2)]
    public object[]? Spid { get; set; }

    /// <summary>Includes system sessions instead of user sessions.</summary>
    [Parameter]
    public SwitchParameter IncludeSystemSpid { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private string _sql = "";

    // PS: $results is a function-scope local - a statement fault keeps the STALE
    // value from the prior instance.
    private object? _results;

    protected override void BeginProcessing()
    {
        // PS: $(if (Test-Bound 'IncludeSystemSpid') {0} else {1}) - an explicit
        // :$false still selects the system branch.
        string predicate = TestBound("IncludeSystemSpid") ? "0" : "1";
        _sql = @"
            SELECT
                [owt].[session_id] AS [Spid],
                [owt].[exec_context_id] AS [Thread],
                [ot].[scheduler_id] AS [Scheduler],
                [owt].[wait_duration_ms] AS [WaitMs],
                [owt].[wait_type] AS [WaitType],
                [owt].[blocking_session_id] AS [BlockingSpid],
                [owt].[resource_description] AS [ResourceDesc],
                CASE [owt].[wait_type]
                    WHEN N'CXPACKET' THEN
                        RIGHT ([owt].[resource_description],
                            CHARINDEX (N'=', REVERSE ([owt].[resource_description])) - 1)
                    ELSE NULL
                END AS [NodeId],
                [eqmg].[dop] AS [Dop],
                [er].[database_id] AS [DbId],
                [est].[text] AS [SqlText],
                [eqp].[query_plan] AS [QueryPlan],
                CAST ('https://www.sqlskills.com/help/waits/' + [owt].[wait_type] AS XML) AS [URL]
            FROM sys.dm_os_waiting_tasks [owt]
            INNER JOIN sys.dm_os_tasks [ot] ON
                [owt].[waiting_task_address] = [ot].[task_address]
            INNER JOIN sys.dm_exec_sessions [es] ON
                [owt].[session_id] = [es].[session_id]
            INNER JOIN sys.dm_exec_requests [er] ON
                [es].[session_id] = [er].[session_id]
            FULL JOIN sys.dm_exec_query_memory_grants [eqmg] ON
                [owt].[session_id] = [eqmg].[session_id]
            OUTER APPLY sys.dm_exec_sql_text ([er].[sql_handle]) [est]
            OUTER APPLY sys.dm_exec_query_plan ([er].[plan_handle]) [eqp]
            WHERE
                [es].[is_user_process] = " + predicate + @"
            ORDER BY
                [owt].[session_id],
                [owt].[exec_context_id]
            OPTION(RECOMPILE);";
    }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Hashtable connectParams = new Hashtable();
            connectParams["SqlInstance"] = instance;
            connectParams["SqlCredential"] = SqlCredential;
            connectParams["MinimumVersion"] = 9;
            NestedConnect.Outcome connection = NestedConnect.Connect(this, connectParams);
            if (!connection.Ok)
            {
                StopFunction("Failure", target: instance, errorRecord: connection.Failure, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }
            Server server = connection.Server!;

            // PS: $results = $server.Query($sql) - NO try; a fault surfaces and the
            // row loop runs with the stale value.
            try
            {
                _results = MethodReturnValue(NestedCommand.InvokeScoped(this, ServerQueryScript, server, _sql));
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException ex)
            {
                StatementFault.Surface(this, ex, "Get-DbaWaitingTask");
            }

            try
            {
                foreach (PSObject? item in NestedCommand.InvokeScoped(this, RowProjectionScript, server, _results, Spid, TestBound("Spid")))
                    WriteObject(item);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException ex)
            {
                StatementFault.Surface(this, ex, "Get-DbaWaitingTask");
            }
        }
    }

    /// <summary>PS method-return shaping through the hop: none = null, the ETS real-null
    /// single element = null, one = the item, many = array.</summary>
    private static object? MethodReturnValue(Collection<PSObject> results)
    {
        if (results.Count == 0)
            return null;
        if (results.Count == 1)
        {
            if (results[0] is null)
                return null;
            return results[0];
        }
        object?[] array = new object?[results.Count];
        for (int n = 0; n < results.Count; n++)
            array[n] = results[n];
        return array;
    }

    // PS: $server.Query($query) on the engine (the W1-046 seam).
    private const string ServerQueryScript = """
param($server, $query)
$server.Query($query)
""";

    // PS: the per-instance row loop VERBATIM (the Test-Bound-gated -notin Spid filter
    // with its contained continue, the 16-prop projection - InfoUrl reads a column the
    // query aliases as [URL], a silent-null DataRow miss - and the SDV exclude triple).
    private const string RowProjectionScript = """
param($server, $results, $Spid, $__spidBound)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($server, $results, $Spid, $__spidBound)
    foreach ($row in $results) {
        if ($__spidBound) {
            if ($row.Spid -notin $Spid) { continue }
        }

        [PSCustomObject]@{
            ComputerName = $server.ComputerName
            InstanceName = $server.ServiceName
            SqlInstance  = $server.DomainInstanceName
            Spid         = $row.Spid
            Thread       = $row.Thread
            Scheduler    = $row.Scheduler
            WaitMs       = $row.WaitMs
            WaitType     = $row.WaitType
            BlockingSpid = $row.BlockingSpid
            ResourceDesc = $row.ResourceDesc
            NodeId       = $row.NodeId
            Dop          = $row.Dop
            DbId         = $row.DbId
            SqlText      = $row.SqlText
            QueryPlan    = $row.QueryPlan
            InfoUrl      = $row.InfoUrl
        } | Select-DefaultView -ExcludeProperty 'SqlText', 'QueryPlan', 'InfoUrl'
    }
} $server $results $Spid $__spidBound 3>&1
""";
}

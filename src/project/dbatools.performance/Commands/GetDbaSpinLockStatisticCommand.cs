#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Lists spinlock statistics. Port of public/Get-DbaSpinLockStatistic.ps1 (W1-099).
/// The BEGIN block debug-logs the query; the process block starts with the (inert here)
/// Test-FunctionInterrupt guard; each instance rides one VERBATIM hop enumerating
/// $server.Query($sql) into the bare 9-prop PSCustomObject projection (no
/// Select-DefaultView). Surface pinned by migration/baselines/Get-DbaSpinLockStatistic.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaSpinLockStatistic")]
public sealed class GetDbaSpinLockStatisticCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private const string Sql = @"SELECT
                    name,
                    collisions,
                    spins,
                    spins_per_collision,
                    sleep_time,
                    backoffs
                FROM sys.dm_os_spinlock_stats;";

    protected override void BeginProcessing()
    {
        // PS: Write-Message -Level Debug -Message $sql
        WriteMessage(MessageLevel.Debug, Sql);
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Hashtable connectParams = new Hashtable();
            connectParams["SqlInstance"] = instance;
            connectParams["SqlCredential"] = SqlCredential;
            connectParams["MinimumVersion"] = 10;
            NestedConnect.Outcome connection = NestedConnect.Connect(this, connectParams);
            if (!connection.Ok)
            {
                StopFunction("Failure", target: instance, errorRecord: connection.Failure, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }
            Server server = connection.Server!;

            try
            {
                foreach (PSObject? item in NestedCommand.InvokeScoped(this, RowProjectionScript, server, Sql))
                    WriteObject(item);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException ex)
            {
                StatementFault.Surface(this, ex, "Get-DbaSpinLockStatistic");
            }
        }
    }

    // PS: foreach ($row in $server.Query($sql)) { [PSCustomObject]@{...} } VERBATIM
    // (the W1-046 seam; a bare PSCustomObject emission, no Select-DefaultView).
    private const string RowProjectionScript = """
param($server, $sql)
foreach ($row in $server.Query($sql)) {
    [PSCustomObject]@{
        ComputerName      = $server.ComputerName
        InstanceName      = $server.ServiceName
        SqlInstance       = $server.DomainInstanceName
        SpinLockName      = $row.name
        Collisions        = $row.collisions
        Spins             = $row.spins
        SpinsPerCollision = $row.spins_per_collision
        SleepTime         = $row.sleep_time
        Backoffs          = $row.backoffs
    }
}
""";
}

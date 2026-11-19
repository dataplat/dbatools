#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Calculates backup throughput statistics from msdb backup history. Port of
/// public/Measure-DbaBackupThroughput.ps1 (W3-060). The workflow remains a module-scoped
/// PowerShell compatibility hop so the nested Get-DbaDbBackupHistory composition (still a
/// PS function during the hybrid period), the -in/-NotIn database gates, the engine's
/// Group-Object averaging with its $db loop-variable reuse, the zero-millisecond throughput
/// branch, and the [DbaSize]/[DbaTimeSpan]/[DbaDateTime] output coercions retain the retired
/// function's engine semantics. Surface pinned by
/// migration/baselines/Measure-DbaBackupThroughput.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Measure, "DbaBackupThroughput")]
public sealed class MeasureDbaBackupThroughputCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The databases to analyze for backup throughput statistics.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The databases to exclude from throughput analysis.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Analyzes only backups taken on or after this date and time.</summary>
    [Parameter(Position = 4)]
    [PsDateTimeCast]
    public DateTime Since { get; set; }

    /// <summary>The backup type to analyze. Defaults to Full.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    [ValidateSet("Full", "Log", "Differential", "File", "Differential File", "Partial Full", "Partial Differential")]
    public string Type { get; set; } = "Full";

    /// <summary>Filters analysis to specific backup device types.</summary>
    [Parameter(Position = 6)]
    public string[]? DeviceType { get; set; }

    /// <summary>Analyzes only the most recent backup for each database.</summary>
    [Parameter]
    public SwitchParameter Last { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // Stream one hop PER INSTANCE: a whole-array hop batches every instance's
        // VeryVerbose/Debug records ahead of all stat output, where the source's foreach
        // interleaves messages-then-stats per instance (the W2-010 Get-DbaAgentAlert
        // Debug-interleave class and fix). The hop body has no cross-instance state.
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;

            // -Since is surface-typed System.DateTime (baseline law), so an unbound Since
            // must travel as $null - not default(DateTime) - for the body's `if ($Since)`
            // truthiness gate to keep the function's unbound behavior.
            NestedCommand.InvokeScopedStreaming(this, item =>
            {
                if (item?.BaseObject is ErrorRecord nestedError)
                {
                    NestedCommand.RemoveDuplicateError(this, nestedError);
                    WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                }
                else
                {
                    WriteObject(item);
                }
            }, BodyScript,
            new[] { instance }, SqlCredential, Database, ExcludeDatabase,
                TestBound(nameof(Since)) ? (object)Since : null, Last.ToBool(), Type,
                DeviceType, EnableException.ToBool(),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
        }
    }

    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Since, $Last, $Type, $DeviceType, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, $Since, $Last, $Type, [string[]]$DeviceType, $EnableException, $__boundVerbose, $__boundDebug)
    # $Since stays untyped in this hop param block: the outer cmdlet passes $null when -Since
    # is unbound and PS faults null-to-[datetime] argument conversion; a bound value arrives
    # as a real DateTime so the truthiness gate below is unchanged either way.

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Measure-DbaBackupThroughput
        }

        if ($Database) {
            $DatabaseCollection = $server.Databases | Where-Object Name -in $Database
        } else {
            $DatabaseCollection = $server.Databases
        }

        if ($ExcludeDatabase) {
            $DatabaseCollection = $DatabaseCollection | Where-Object Name -NotIn $ExcludeDatabase
        }

        foreach ($db in $DatabaseCollection) {
            Write-Message -Level VeryVerbose -Message "Retrieving history for $db." -FunctionName Measure-DbaBackupThroughput -ModuleName "dbatools"
            $allHistory = @()

            # Splatting didn't work
            if ($Since) {
                $histories = Get-DbaDbBackupHistory -SqlInstance $server -Database $db.name -Since $Since -DeviceType $DeviceType -Type $Type
            } else {
                $histories = Get-DbaDbBackupHistory -SqlInstance $server -Database $db.name -Last:$Last -DeviceType $DeviceType -Type $Type
            }

            foreach ($history in $histories) {
                $timeTaken = New-TimeSpan -Start $history.Start -End $history.End

                if ($timeTaken.TotalMilliseconds -eq 0) {
                    $throughput = $history.TotalSize.Megabyte
                } else {
                    $throughput = $history.TotalSize.Megabyte / $timeTaken.TotalSeconds
                }

                Add-Member -Force -InputObject $history -MemberType NoteProperty -Name MBps -value $throughput

                $allHistory += $history | Select-Object ComputerName, InstanceName, SqlInstance, Database, MBps, TotalSize, Start, End
            }

            Write-Message -Level VeryVerbose -Message "Calculating averages for $db." -FunctionName Measure-DbaBackupThroughput -ModuleName "dbatools"
            foreach ($db in ($allHistory | Sort-Object Database | Group-Object Database)) {

                $measureMb = $db.Group.MBps | Measure-Object -Average -Minimum -Maximum
                $measureStart = $db.Group.Start | Measure-Object -Minimum
                $measureEnd = $db.Group.End | Measure-Object -Maximum
                $measureSize = $db.Group.TotalSize.Megabyte | Measure-Object -Average
                $avgDuration = $db.Group | ForEach-Object { New-TimeSpan -Start $_.Start -End $_.End } | Measure-Object -Average TotalSeconds

                [PSCustomObject]@{
                    ComputerName  = $db.Group.ComputerName | Select-Object -First 1
                    InstanceName  = $db.Group.InstanceName | Select-Object -First 1
                    SqlInstance   = $db.Group.SqlInstance | Select-Object -First 1
                    Database      = $db.Name
                    AvgThroughput = [DbaSize]([System.Math]::Round($measureMb.Average, 2) * 1024 * 1024)
                    AvgSize       = [DbaSize]([System.Math]::Round($measureSize.Average, 2) * 1024 * 1024)
                    AvgDuration   = [DbaTimeSpan](New-TimeSpan -Seconds $avgDuration.Average)
                    MinThroughput = [DbaSize]([System.Math]::Round($measureMb.Minimum, 2) * 1024 * 1024)
                    MaxThroughput = [DbaSize]([System.Math]::Round($measureMb.Maximum, 2) * 1024 * 1024)
                    MinBackupDate = [DbaDateTime]$measureStart.Minimum
                    MaxBackupDate = [DbaDateTime]$measureEnd.Maximum
                    BackupCount   = $db.Count
                }
            }
        }
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Since $Last $Type $DeviceType $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Compares Query Store settings against recommended values. Port of
/// public/Test-DbaDbQueryStore.ps1; the workflow remains a module-scoped PowerShell compatibility
/// hop.
///
/// $ExcludeDatabase is CROSS-RECORD MUTABLE STATE and is the reason this port carries a sentinel.
/// The script function mutates it twice, and both mutations outlive the statement that made them
/// because the variable is function-scope:
///   begin:   $ExcludeDatabase += "master", "model", "tempdb"   (once per invocation)
///   process: $ExcludeDatabase += "msdb"                        (per element, only on Azure)
/// The second one matters. Once ANY element turns out to be an Azure database, the function
/// excludes msdb for every later element AND every later pipeline record. A hop-local would reset
/// on the next record and silently start including msdb again.
///
/// The carry has a sharp edge that the obvious implementation gets wrong. The begin append is only
/// harmless-per-hop while nothing is carried, because each hop re-binds $ExcludeDatabase from the
/// cmdlet property and so produces the same array every time. The moment a value IS carried,
/// appending the three system databases again on the next hop would COMPOUND the array. So the hop
/// either restores the carried value or runs the begin append - never both. That is why the begin
/// line is guarded rather than simply placed at the top of the body.
///
/// The sentinel is emitted from a finally, because the process body has two early `return` paths -
/// the "you must pipe in a database or a server" guard and the default branch of the input-type
/// switch - and a carrier emitted at the end of the body would be skipped by both, losing the
/// accumulated exclusions.
///
/// This port keeps the WHOLE-ARRAY hop rather than splitting per element. The per-element ruling
/// applies to instance loops that hold no cross-instance state; this loop is over $InputObject and
/// accumulates $ExcludeDatabase across its elements, which is the ruling's stated exemption.
///
/// Note that -SqlInstance is NOT pipeline-bound here; -InputObject is, and the process body
/// re-points $InputObject at $SqlInstance when the latter was supplied.
///
/// Two source quirks ship unrepaired, because parity is the contract, not tidiness:
///   * the connection catch reads -Target $instance, a variable this function never assigns
///     anywhere (the element loop variable is $input), so it passes $null;
///   * the element loop variable IS $input, shadowing the PowerShell automatic. That was probed
///     across the function, module-scriptblock and production-hop shapes and behaves identically
///     in all three, so it needs no shim.
///
/// The hop streams rather than buffers: the command emits one object per Query Store property per
/// database, and a caller can legitimately stop early.
///
/// $EnableException is passed into the hop because Stop-Function's own parameter block defaults it
/// from the caller's scope. Every in-hop Stop-Function and Write-Message carries -FunctionName,
/// because both derive the reporting command from the call stack, which is a scriptblock in a hop.
/// Cross-record graceful-stop state is held by the base cmdlet's Interrupted flag, checked before
/// each record, which is what the function's own Test-FunctionInterrupt guard did across records.
///
/// The source declares plain [CmdletBinding()], so this cmdlet does NOT declare
/// SupportsShouldProcess. Parameter positions are pinned from the golden baseline.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaDbQueryStore")]
[OutputType(typeof(PSObject))]
public sealed class TestDbaDbQueryStoreCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only check these databases.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Skip these databases. The system databases are always added to this list.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Server or database objects, typically from Get-DbaDatabase.</summary>
    [Parameter(Position = 4, ValueFromPipeline = true)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The accumulated $ExcludeDatabase, carried between records. _hasState distinguishes "no record
    // has run yet" from "a record ran and produced this value", which is what decides whether the
    // begin append runs or the carried value is restored.
    private object? _excludeDatabaseState;
    private bool _hasExcludeDatabaseState;

    // The graceful-stop latch, carried between records. The base cmdlet's Interrupted flag is only
    // raised by the C# StopFunction helper; nothing bridges a Stop-Function called INSIDE the hop,
    // and that one writes a hop-scope variable that dies with the record. Without carrying it, the
    // process body's own Test-FunctionInterrupt guard can never fire on a later record.
    private bool _interrupted;

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__testDbaDbQueryStoreState"]?.Value))
            {
                _excludeDatabaseState = item.Properties["ExcludeDatabase"]?.Value;
                _hasExcludeDatabaseState = true;
                _interrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BodyScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, InputObject,
            EnableException.ToBool(), _excludeDatabaseState, _hasExcludeDatabaseState, _interrupted,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source's process body VERBATIM, wrapped so $ExcludeDatabase survives between records.
    // Substitutions only: -FunctionName Test-DbaDbQueryStore on every Stop-Function/Write-Message,
    // and the begin append is guarded so it cannot compound onto a restored value.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $InputObject, $EnableException, $__excludeState, $__hasExcludeState, $__carriedInterrupt, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, [object[]]$InputObject, $EnableException, $__excludeState, $__hasExcludeState, $__carriedInterrupt, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # Restore the graceful-stop latch an earlier record set. Stop-Function signals a stop by writing
    # this variable into its caller's scope, and Test-FunctionInterrupt reads it back with
    # Get-Variable -Scope 1. In the script function that scope is the function's own, so the latch
    # survives from one record to the next and the guard at the top of the process body short-circuits
    # every later record. A hop scope dies with its record, so without this the guard never fires
    # again and each record repeats work the function had already stopped doing. Seeding it here lets
    # the body's own verbatim Test-FunctionInterrupt line do the short-circuiting, unchanged.
    if ($__carriedInterrupt) {
        Set-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -Scope 0 -Value $true
    }

    try {
        # The function's begin block, which runs ONCE per invocation. On every record after the
        # first the accumulated value is restored instead - appending the system databases again
        # would compound them onto an array that already contains them.
        if ($__hasExcludeState) {
            $ExcludeDatabase = $__excludeState
        } else {
            $ExcludeDatabase += "master", "model", "tempdb"
        }

            if (Test-FunctionInterrupt) { return }

            if (-not $InputObject -and -not $SqlInstance) {
                Stop-Function -Message "You must pipe in a database or a server, or specify a SqlInstance" -FunctionName Test-DbaDbQueryStore
                return
            }

            if ($SqlInstance) {
                $InputObject = $SqlInstance
            }

            foreach ($input in $InputObject) {
                $inputType = $input.GetType().FullName

                switch ($inputType) {
                    'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                        Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject" -FunctionName Test-DbaDbQueryStore -ModuleName "dbatools"
                        $dbDatabases = Get-DbaDatabase -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -OnlyAccessible
                    }
                    'Microsoft.SqlServer.Management.Smo.Server' {
                        Write-Message -Level Verbose -Message "Processing Server through InputObject" -FunctionName Test-DbaDbQueryStore -ModuleName "dbatools"
                        $dbDatabases = Get-DbaDatabase -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -OnlyAccessible
                    }
                    'Microsoft.SqlServer.Management.Smo.Database' {
                        Write-Message -Level Verbose -Message "Processing Database through InputObject" -FunctionName Test-DbaDbQueryStore -ModuleName "dbatools"
                        $dbDatabases = $input | Where-Object { $_.Name -notin $ExcludeDatabase }
                    }
                    default {
                        Stop-Function -Message "InputObject is not a server or database." -FunctionName Test-DbaDbQueryStore
                        return
                    }
                }

                try {
                    $server = Connect-DbaInstance -SqlInstance $dbDatabases[0].Parent -SqlCredential $SqlCredential -MinimumVersion 13
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaDbQueryStore
                }

                if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                    $ExcludeDatabase += "msdb"
                }

                if ($Database) {
                    $dbDatabases = $dbDatabases | Where-Object { $Database -contains $_.Name }
                }

                if ($ExcludeDatabase) {
                    $dbDatabases = $dbDatabases | Where-Object Name -NotIn $ExcludeDatabase
                }

                $desiredState = [PSCustomObject]@{
                    Property      = 'ActualState'
                    Value         = 'ReadWrite'
                    Justification = 'This means Query Store is enabled and collecting data.'
                },
                [PSCustomObject]@{
                    Property      = 'DataFlushIntervalInSeconds'
                    Value         = '900'
                    Justification = 'Recommended to leave this at the default of 900 seconds (15 mins).'
                },
                [PSCustomObject]@{
                    Property      = 'MaxPlansPerQuery'
                    Value         = '200'
                    Justification = 'Number of distinct plans per query. 200 is a good starting point for most environments.'
                },
                [PSCustomObject]@{
                    Property      = 'MaxStorageSizeInMB'
                    Value         = '2048'
                    Justification = 'How much disk space Query Store will use. 2GB is a good starting point.'
                },
                [PSCustomObject]@{
                    Property      = 'QueryCaptureMode'
                    Value         = 'Auto'
                    Justification = 'With auto, queries that are insignificant from a resource utilization perspective, or executed infrequently, are not captured.'
                },
                [PSCustomObject]@{
                    Property      = 'SizeBasedCleanupMode'
                    Value         = 'Auto'
                    Justification = 'With auto, as Query Store gets close to out of space it will automatically purge older data.'
                },
                [PSCustomObject]@{
                    Property      = 'StaleQueryThresholdInDays'
                    Value         = '30'
                    Justification = 'Determines how much historic data to keep. 30 days is a good value here.'
                },
                [PSCustomObject]@{
                    Property      = 'StatisticsCollectionIntervalInMinutes'
                    Value         = '30'
                    Justification = 'Time window that runtime stats will be aggregated. Use 30 unless you have space concerns, then leave at the default (60).'
                },
                [PSCustomObject]@{
                    Property      = 'WaitStatsCaptureMode'
                    Value         = 'ON'
                    Justification = 'Adds valuable data when troubleshooting.'
                }

                try {
                    Write-Message -Level Verbose -Message "Evaluating Query Store options" -FunctionName Test-DbaDbQueryStore -ModuleName "dbatools"
                    $currentOptions = Get-DbaDbQueryStoreOption -SqlInstance $server -Database $dbDatabases.name

                    foreach ($db in $currentOptions) {
                        $props = $db.GetPropertySet() | Where-Object Name -NotIn ('CurrentStorageSizeInMB', 'ReadOnlyReason', 'DesiredState')
                        foreach ($property in $props) {
                            [PSCustomObject]@{
                                ComputerName     = $db.ComputerName
                                InstanceName     = $db.InstanceName
                                SqlInstance      = $db.SqlInstance
                                Database         = $db.Database
                                Name             = $property.Name
                                Value            = $property.Value
                                RecommendedValue = ($desiredState | Where-Object Property -EQ $property.Name).Value
                                IsBestPractice   = ($property.Value -eq ($desiredState | Where-Object Property -EQ $property.Name).Value)
                                Justification    = ($desiredState | Where-Object Property -EQ $property.Name).Justification
                            }
                        }
                    }
                } catch {
                    Stop-Function -Message "Unable to get Query Store data $server" -Target $server -ErrorRecord $_ -FunctionName Test-DbaDbQueryStore
                }

                if ($server.DatabaseEngineType -ne "SqlAzureDatabase") {
                    # Trace flags
                    $queryStoreTF = [PSCustomObject]@{
                        TraceFlag     = '7745'
                        Justification = 'SQL Server will not wait to write Query Store data to disk on shutdown\failover (can cause lose of Query Store data).'
                    },
                    [PSCustomObject]@{
                        TraceFlag     = '7752'
                        Justification = 'Load Query Store data asynchronously on SQL Server startup.'
                    }
                    try {
                        foreach ($tf in $queryStoreTF) {
                            if (($server.MajorVersion -lt 15 -and $tf.TraceFlag -eq 7752) -or $tf.TraceFlag -eq 7745) {
                                $tfEnabled = Get-DbaTraceFlag -SqlInstance $server -TraceFlag $tf.TraceFlag
                                [PSCustomObject]@{
                                    ComputerName     = $server.ComputerName
                                    InstanceName     = $server.DbaInstanceName
                                    SqlInstance      = $server.Name
                                    Name             = ('Trace Flag {0} Enabled' -f $tf.TraceFlag)
                                    Value            = if ($tfEnabled) { 'Enabled' } else { 'Disabled' }
                                    RecommendedValue = $tf.TraceFlag
                                    IsBestPractice   = ($tfEnabled.TraceFlag -eq $tf.TraceFlag)
                                    Justification    = $tf.Justification
                                }
                                $tfEnabled = $null
                            }
                        }
                    } catch {
                        Stop-Function -Message "Unable to get Trace Flag data $server" -Target $server -ErrorRecord $_ -FunctionName Test-DbaDbQueryStore
                    }
                }
            }

    } finally {
        # From a finally, because the body above has two early returns that would otherwise skip
        # the carrier and lose an msdb exclusion an earlier element established, or lose a stop
        # latch a Stop-Function in this record just set.
        [pscustomobject]@{
            __testDbaDbQueryStoreState = $true
            ExcludeDatabase            = $ExcludeDatabase
            Interrupted                = [bool](Test-FunctionInterrupt)
        }
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $InputObject $EnableException $__excludeState $__hasExcludeState $__carriedInterrupt $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Measures VLF counts per database. Port of public/Measure-DbaDbVirtualLogFile.ps1
/// (W1-110). The database walk applies the VALUE-truthy -Database/-ExcludeDatabase gates
/// (W1-065 law) and the !$IncludeSystemDBs `IsSystemObject -eq $false` filter (NO
/// IsAccessible filter - offline databases flow through and the nested fetches come back
/// empty exactly as the function's did); the whole per-database try body then rides ONE
/// VERBATIM module hop (nested Get-DbaDbVirtualLogFile + Get-DbaDbFile calls with the
/// W1-105 wrapper server, the Where-Object Status splits, the PS3+ intrinsic .Count reads
/// with the dead PSv2 `$null -eq .Count` guard, the member-enumeration -join projections
/// and the Select-DefaultView emission) so the engine's own semantics decide every quirk;
/// merged-back 2&gt;&amp;1 records re-emit through WriteError with the W1-045 silent-bag
/// compensation, and a terminating hop fault lands in the catch's Stop-Function
/// "Unable to query..." -Continue. Surface pinned by
/// migration/baselines/Measure-DbaDbVirtualLogFile.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Measure, "DbaDbVirtualLogFile")]
[OutputType(typeof(System.Collections.ArrayList))]
public sealed class MeasureDbaDbVirtualLogFileCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The databases to analyze.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The databases to skip.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Include the system databases (excluded by default).</summary>
    [Parameter]
    public SwitchParameter IncludeSystemDBs { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Hashtable connectParams = new Hashtable();
            connectParams["SqlInstance"] = instance;
            connectParams["SqlCredential"] = SqlCredential;
            NestedConnect.Outcome connection = NestedConnect.Connect(this, connectParams);
            if (!connection.Ok)
            {
                StopFunction("Failure", target: instance, errorRecord: connection.Failure, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }
            Server server = connection.Server!;
            // PS: $server keeps Connect-DbaInstance's wrapper (the W1-105 dispatch law).
            object serverValue = connection.RawServerValue ?? connection.Server!;

            // PS: $dbs = $server.Databases | Where-Object chains - Name -in, Name -NotIn,
            // IsSystemObject -eq $false (no IsAccessible filter in this function).
            bool filterInclude = PsTruthy(Database);
            bool filterExclude = PsTruthy(ExcludeDatabase);
            List<Microsoft.SqlServer.Management.Smo.Database> dbs = new List<Microsoft.SqlServer.Management.Smo.Database>();
            foreach (Microsoft.SqlServer.Management.Smo.Database candidate in server.Databases)
            {
                if (filterInclude && !MatchesAny(candidate.Name, Database!))
                    continue;
                if (filterExclude && MatchesAny(candidate.Name, ExcludeDatabase!))
                    continue;
                if (!IncludeSystemDBs.IsPresent && !PsOps.Eq(candidate.IsSystemObject, false))
                    continue;
                dbs.Add(candidate);
            }

            foreach (Microsoft.SqlServer.Management.Smo.Database db in dbs)
            {
                try
                {
                    foreach (PSObject? item in NestedCommand.InvokeScoped(this, DatabaseScript, serverValue, db, BoundVerbose(), BoundDebug()))
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
                    }
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    StopFunction("Unable to query " + db.Name + " on " + PsText(instance) + ".", target: db, errorRecord: StatementFault.Record(ex, "Measure-DbaDbVirtualLogFile"), continueLoop: true);
                    continue;
                }
            }
        }
    }

    /// <summary>PS array truthiness: empty = false, one element = its truthiness,
    /// two or more = true.</summary>
    private static bool PsTruthy(object[]? values)
    {
        if (values is null || values.Length == 0)
            return false;
        if (values.Length == 1)
            return LanguagePrimitives.IsTrue(values[0]);
        return true;
    }

    /// <summary>PS -in over the filter array (elementwise -eq with the ELEMENT as the
    /// left operand, so a non-string filter value drives the coercion - codex W1-110 r1:
    /// -Database 1 matches a database named "01" exactly like the function did).</summary>
    private static bool MatchesAny(string name, object[] values)
    {
        return PsOps.In(name, values);
    }

    /// <summary>PS string interpolation via LanguagePrimitives (invariant).</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return (string)LanguagePrimitives.ConvertTo(value, typeof(string), CultureInfo.InvariantCulture);
    }

    /// <summary>A bound -Debug carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundDebug()
    {
        object? debug;
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    /// <summary>A bound -Verbose carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundVerbose()
    {
        object? verbose;
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    // PS: the whole per-database try body VERBATIM in the dbatools module scope - the
    // nested command calls, the Where-Object splits, the intrinsic .Count reads, the
    // member-enumeration -joins, the [PSCustomObject] literal and the Select-DefaultView
    // emission all run on the engine exactly as the function ran them.
    private const string DatabaseScript = """
param($server, $db, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($server, $db, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    $data = Get-DbaDbVirtualLogFile -SqlInstance $server -Database $db.Name
    $logFile = Get-DbaDbFile -SqlInstance $server -Database $db.Name | Where-Object Type -eq 1

    $active = $data | Where-Object Status -eq 2
    $inactive = $data | Where-Object Status -eq 0

    [PSCustomObject]@{
        ComputerName      = $server.ComputerName
        InstanceName      = $server.ServiceName
        SqlInstance       = $server.DomainInstanceName
        Database          = $db.name
        Total             = $data.Count
        TotalCount        = $data.Count
        Inactive          = if ($inactive -and $null -eq $inactive.Count) { 1 } else { $inactive.Count }
        Active            = if ($active -and $null -eq $active.Count) { 1 } else { $active.Count }
        LogFileName       = $logFile.LogicalName -join ","
        LogFileGrowth     = $logFile.Growth -join ","
        LogFileGrowthType = $logFile.GrowthType -join ","
    } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Database, Total
} $server $db $__boundVerbose $__boundDebug 3>&1 2>&1
""";
}

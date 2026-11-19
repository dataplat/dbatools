#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests whether databases are REALLY in their configured recovery model (the
/// pseudo-Simple detection). Port of public/Test-DbaDbRecoveryModel.ps1 (W3-108).
/// Begin + per-record hops; no end block. CLASSIFICATION TABLE (SqlInstance is the
/// VFP; promoted question answered): begin state read by process = $sql (built once,
/// incl. the UNDECLARED $databasefilter += string-concat quirk and the injected
/// $recoveryCode) and $RecoveryModel (MUTATED to "Full" when unbound via the
/// Test-Bound -Not default) - both ride the __w3108State sentinel; process locals are
/// per-iteration. The single Test-Bound -Not call rides as a NEGATED carried flag
/// (W3-093 law). NO ShouldProcess (plain CmdletBinding, no WhatIf/Confirm plumbing);
/// no Test-FunctionInterrupt in the source; both Stop-Function sites use -Continue
/// INSIDE the per-record foreach (the W3-102 relay and W3-103 latch classes verified
/// N/A). Checklist greps done: Select-DefaultView is a scope-walk-free, callstack-free
/// PS function; hop-frame Stop-Function/Write-Message carry -FunctionName (W1-090). No
/// bind-time casts ([object]/[object[]] params; the ValidateSet on RecoveryModel is
/// mirrored). [OutputType("System.Collections.ArrayList")] mirrored - it is part of
/// the pinned surface. Surface pinned by
/// migration/baselines/Test-DbaDbRecoveryModel.json (no sets, implicit positions:
/// SqlInstance Mandatory pos0 VFP, Database pos1, ExcludeDatabase pos2, SqlCredential
/// pos3, RecoveryModel pos4).
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaDbRecoveryModel")]
[OutputType("System.Collections.ArrayList")]
public sealed class TestDbaDbRecoveryModelCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Database filter.</summary>
    [Parameter(Position = 1)]
    public object[]? Database { get; set; }

    /// <summary>Database exclusion filter.</summary>
    [Parameter(Position = 2)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Credential for SQL Server authentication.</summary>
    [Parameter(Position = 3)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Recovery model to test for; defaults to Full.</summary>
    [Parameter(Position = 4)]
    [ValidateSet("Full", "Simple", "Bulk_Logged")]
    public object? RecoveryModel { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // begin-built query + the begin-defaulted RecoveryModel.
    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Database, ExcludeDatabase, RecoveryModel, TestBound(nameof(RecoveryModel)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3108State"))
            {
                _state = sentinel["__w3108State"] as Hashtable;
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, EnableException.ToBool(), _state,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block VERBATIM. Substitution only: Test-Bound -ParameterName
    // RecoveryModel -Not -> the negated carried flag (W3-093 law). The built $sql and
    // the possibly-defaulted $RecoveryModel ride the sentinel to the process hops.
    private const string BeginScript = """
param($Database, $ExcludeDatabase, $RecoveryModel, $__boundRecoveryModel, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([object[]]$Database, [object[]]$ExcludeDatabase, [object]$RecoveryModel, $__boundRecoveryModel, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (-not $__boundRecoveryModel) {
        $RecoveryModel = "Full"
    }

    switch ($RecoveryModel) {
        "Full" { $recoveryCode = 1 }
        "Bulk_Logged" { $recoveryCode = 2 }
        "Simple" { $recoveryCode = 3 }
    }

    $sqlRecoveryModel = "SELECT SERVERPROPERTY('MachineName') AS ComputerName,
                ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                SERVERPROPERTY('ServerName') AS SqlInstance
                        , d.[name] AS [Database]
                        , d.recovery_model AS RecoveryModel
                        , d.recovery_model_desc AS RecoveryModelDesc
                        , CASE
                            WHEN d.recovery_model = 1 AND drs.last_log_backup_lsn IS NOT NULL THEN 1
                            ELSE 0
                           END AS IsReallyInFullRecoveryModel
                  FROM sys.databases AS d
                    INNER JOIN sys.database_recovery_status AS drs
                       ON d.database_id = drs.database_id
                  WHERE d.recovery_model = $recoveryCode"

    if ($Database) {
        $dblist = $Database -join "','"
        $databasefilter += "AND d.[name] in ('$dblist')"
    }
    if ($ExcludeDatabase) {
        $dblist = $ExcludeDatabase -join "','"
        $databasefilter += "AND d.[name] NOT IN ('$dblist')"
    }

    $sql = "$sqlRecoveryModel $databasefilter"

    Write-Message -Level Debug -Message $sql -FunctionName Test-DbaDbRecoveryModel -ModuleName "dbatools"

    @{ __w3108State = @{ sql = $sql; RecoveryModel = $RecoveryModel } }
} $Database $ExcludeDatabase $RecoveryModel $__boundRecoveryModel $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process body VERBATIM per record; $sql and the defaulted $RecoveryModel
    // restore from the sentinel. Substitutions only: explicit -FunctionName
    // Test-DbaDbRecoveryModel on hop-frame Stop-Function/Write-Message (W1-090).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $EnableException, $__state, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, $EnableException, $__state, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        $sql = $__state.sql
        $RecoveryModel = $__state.RecoveryModel

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaDbRecoveryModel
            }

            try {
                $results = $server.Query($sql)

                if (-not $results) {
                    Write-Message -Level Verbose -Message "Server '$instance' does not have any databases in the $RecoveryModel recovery model." -FunctionName Test-DbaDbRecoveryModel -ModuleName "dbatools"
                }

                foreach ($row in $results) {
                    if (!([bool]$row.IsReallyInFullRecoveryModel) -and $RecoveryModel -eq 'Full') {
                        $ActualRecoveryModel = "SIMPLE"
                    } else {
                        $ActualRecoveryModel = "$($RecoveryModel.ToString().ToUpper())"
                    }

                    [PSCustomObject]@{
                        ComputerName            = $row.ComputerName
                        InstanceName            = $row.InstanceName
                        SqlInstance             = $row.SqlInstance
                        Database                = $row.Database
                        ConfiguredRecoveryModel = $row.RecoveryModelDesc
                        ActualRecoveryModel     = $ActualRecoveryModel
                    } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Database, ConfiguredRecoveryModel, ActualRecoveryModel
                }
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaDbRecoveryModel
            }
        }
    }
} $SqlInstance $SqlCredential $EnableException $__state $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

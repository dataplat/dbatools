#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Gets database restore history from msdb. Port of public/Get-DbaDbRestoreHistory.ps1 (W3-030). A
/// READ-ONLY getter (queries msdb.dbo.restorehistory via T-SQL and emits; no mutation). Pure per-record
/// process command with no begin/end blocks. DEF-001 cond1+cond2: the process foreach EMITS the query
/// results (Select-DefaultView) AND has reachable Stop-Function -Continue at Connect-DbaInstance and the
/// outer catch, so the hop STREAMS via InvokeScopedStreaming. Cross-record-state check: $where and
/// $wherearray are re-initialized each record, and the filter set-condition ($ExcludeDatabase/$Database/
/// $Since/$Last) is call-constant across pipeline records - so $where is deterministic per record, not a
/// stale carry. $Since is plain DateTime on the cmdlet (surface parity with the function's type);
/// the C# passes null into the hop when Since was never bound, and $Since is left UNTYPED in the hop param to
/// avoid a null-to-MinValue coercion. No ShouldProcess. Positions match the retired function
/// (SqlInstance=0, SqlCredential=1, Database=2, ExcludeDatabase=3, Since=4, RestoreType=5; Force/Last/
/// EnableException=switch/null) and RestoreType's ValidateSet is preserved. Substitution only: explicit
/// -FunctionName Get-DbaDbRestoreHistory on Stop-Function (W1-090); the body is otherwise verbatim.
/// Surface pinned by migration/baselines/Get-DbaDbRestoreHistory.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaDbRestoreHistory")]
public sealed class GetDbaDbRestoreHistoryCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Database(s) to include.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Only restores since this date/time.</summary>
    [Parameter(Position = 4)]
    public DateTime Since { get; set; }

    /// <summary>Returns all columns (raw) instead of the curated projection.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>Returns only the last restore per database.</summary>
    [Parameter]
    public SwitchParameter Last { get; set; }

    /// <summary>Filters to a specific restore type.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    [ValidateSet("Database", "File", "Filegroup", "Differential", "Log", "Verifyonly", "Revert")]
    public string? RestoreType { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

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
            SqlInstance, SqlCredential, Database, ExcludeDatabase,
            // Surface parity pins Since to plain DateTime (the function's type); unbound-vs-bound
            // is preserved by passing null into the untyped hop param when the caller never bound
            // it (a nullable property would change the public ParameterType).
            MyInvocation.BoundParameters.ContainsKey("Since") ? (object)Since : null,
            Force.ToBool(), Last.ToBool(), RestoreType, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM per record (no begin/end blocks). $Since is left untyped to keep an
    // unbound $null as $null. Substitution only: explicit -FunctionName Get-DbaDbRestoreHistory on
    // Stop-Function (W1-090).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Since, $Force, $Last, $RestoreType, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, $Since, $Force, $Last, [string]$RestoreType, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($instance in $SqlInstance) {
        try {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Get-DbaDbRestoreHistory
            }
            $computername = $server.ComputerName
            $instanceName = $server.ServiceName
            $servername = $server.DomainInstanceName

            if ($force -eq $true) {
                $select = "SELECT '$computername' AS [ComputerName],
                '$instanceName' AS [InstanceName],
                '$servername' AS [SqlInstance], * "
            } else {
                $select = "SELECT
                '$computername' AS [ComputerName],
                '$instanceName' AS [InstanceName],
                '$servername' AS [SqlInstance],
                 rsh.destination_database_name AS [Database],
                 --rsh.restore_history_id as RestoreHistoryID,
                 rsh.user_name AS [Username],
                 CASE
                     WHEN rsh.restore_type = 'D' THEN 'Database'
                     WHEN rsh.restore_type = 'F' THEN 'File'
                     WHEN rsh.restore_type = 'G' THEN 'Filegroup'
                     WHEN rsh.restore_type = 'I' THEN 'Differential'
                     WHEN rsh.restore_type = 'L' THEN 'Log'
                     WHEN rsh.restore_type = 'V' THEN 'Verifyonly'
                     WHEN rsh.restore_type = 'R' THEN 'Revert'
                     ELSE rsh.restore_type
                 END AS [RestoreType],
                 rsh.restore_date AS [Date],
                 ISNULL(STUFF((SELECT ', ' + bmf.physical_device_name
                                FROM msdb.dbo.backupmediafamily bmf
                               WHERE bmf.media_set_id = bs.media_set_id
                             FOR XML PATH('')), 1, 2, ''), '') AS [From],
                 ISNULL(STUFF((SELECT ', ' + rf.destination_phys_name
                                FROM msdb.dbo.restorefile rf
                               WHERE rsh.restore_history_id = rf.restore_history_id
                             FOR XML PATH('')), 1, 2, ''), '') AS [To],
                bs.first_lsn,
                bs.last_lsn,
                bs.checkpoint_lsn,
                bs.database_backup_lsn,
                bs.backup_start_date,
                bs.backup_start_date AS BackupStartDate,
                bs.backup_finish_date,
                bs.backup_finish_date AS BackupFinishDate,
                rsh.stop_at AS StopAt,
                COALESCE(rsh.stop_at, bs.backup_start_date) AS LastRestorePoint
                "
            }

            $from = " FROM msdb.dbo.restorehistory rsh
                INNER JOIN msdb.dbo.backupset bs ON rsh.backup_set_id = bs.backup_set_id"

            if ($ExcludeDatabase -or $Database -or $Since -or $last) {
                $where = " WHERE "
            }

            $wherearray = @()

            if ($ExcludeDatabase) {
                $dblist = $ExcludeDatabase -join "','"
                $wherearray += " destination_database_name not in ('$dblist')"
            }

            if ($Database) {
                $dblist = $Database -join "','"
                $wherearray += "destination_database_name in ('$dblist')"
            }

            if ($null -ne $Since) {
                $wherearray += "rsh.restore_date >= CONVERT(datetime,'$($Since.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126)"
            }

            if ($last) {
                $wherearray += "rsh.restore_history_id IN
                    (SELECT MAX(restore_history_id) FROM msdb.dbo.restorehistory
                    GROUP BY destination_database_name
                    )"
            }

            if ($RestoreType) {
                $wherearray += "rsh.restore_type =
                                    (CASE
                                        WHEN '$RestoreType' = 'Database'        THEN 'D'
                                        WHEN '$RestoreType' = 'File'            THEN 'F'
                                        WHEN '$RestoreType' = 'Filegroup'       THEN 'G'
                                        WHEN '$RestoreType' = 'Differential'    THEN 'I'
                                        WHEN '$RestoreType' = 'Log'             THEN 'L'
                                        WHEN '$RestoreType' = 'Verifyonly'      THEN 'V'
                                        WHEN '$RestoreType' = 'Revert'          THEN 'R'
                                        ELSE 'D'
                                    END)"
            }

            if ($where.length -gt 0) {
                $wherearray = $wherearray -join " and "
                $where = "$where $wherearray"
            }

            $sql = "$select $from $where"

            Write-Message -Level Debug -Message $sql -FunctionName Get-DbaDbRestoreHistory -ModuleName "dbatools"

            $results = $server.ConnectionContext.ExecuteWithResults($sql).Tables.Rows
            if ($last) {
                $ga = $results | Group-Object Database
                $tmpres = @()
                foreach ($g in $ga) {
                    $tmpres += $g.Group | Sort-Object -Property Date -Descending | Select-Object -First 1
                }
                $results = $tmpres
            }
            $results | Select-DefaultView -ExcludeProperty first_lsn, last_lsn, checkpoint_lsn, database_backup_lsn, backup_start_date, backup_finish_date
        } catch {
            Stop-Function -Message "Failure" -Target $SqlInstance -Error $_ -Exception $_.Exception.InnerException -Continue -FunctionName Get-DbaDbRestoreHistory
        }
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Since $Force $Last $RestoreType $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Executes Adam Machanic's sp_WhoIsActive against one or more instances and returns the active-session
/// result set. The per-instance connect, the $PSBoundParameters-to-@sql_parameter mapping and the
/// Invoke-DbaQuery emission remain a module-scoped PowerShell compatibility hop; this cmdlet supplies the
/// parameter surface and threads its own bound-parameter dictionary in as $__bound (the caller's
/// $PSBoundParameters is invisible inside the module scope). The source begin block only massages that
/// dictionary (compute $passedParams, lower-case the two *FilterType values) with no module or SMO work and
/// no cross-record state, so it is folded into the per-record hop bug-for-bug. Surface pinned by
/// migration/baselines/Invoke-DbaWhoIsActive.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaWhoIsActive")]
public sealed class InvokeDbaWhoIsActiveCommand : DbaBaseCmdlet
{
    // The source advanced function declares no explicit Position on any parameter, so PowerShell's default
    // positional binding auto-assigns positions to the non-switch parameters in declaration order (0-16);
    // switches stay named-only. The compiled cmdlet pins those same positions to keep the surface
    // byte-identical to migration/baselines/Invoke-DbaWhoIsActive.json.

    /// <summary>The target SQL Server instance or instances (SQL 2005+).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database where sp_WhoIsActive is installed (defaults to master).</summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    public string? Database { get; set; }

    /// <summary>Include only sessions matching the criteria (supports % and _).</summary>
    [Parameter(Position = 3)]
    [ValidateLength(0, 128)]
    [PsStringCast]
    public string? Filter { get; set; }

    /// <summary>The filter dimension for -Filter.</summary>
    [Parameter(Position = 4)]
    [ValidateSet("Session", "Program", "Database", "Login", "Host")]
    [PsStringCast]
    public string FilterType { get; set; } = "Session";

    /// <summary>Exclude sessions matching the criteria (supports % and _).</summary>
    [Parameter(Position = 5)]
    [ValidateLength(0, 128)]
    [PsStringCast]
    public string? NotFilter { get; set; }

    /// <summary>The filter dimension for -NotFilter.</summary>
    [Parameter(Position = 6)]
    [ValidateSet("Session", "Program", "Database", "Login", "Host")]
    [PsStringCast]
    public string NotFilterType { get; set; } = "Session";

    /// <summary>Include the session running sp_WhoIsActive.</summary>
    [Parameter]
    public SwitchParameter ShowOwnSpid { get; set; }

    /// <summary>Include internal SQL Server system sessions.</summary>
    [Parameter]
    public SwitchParameter ShowSystemSpids { get; set; }

    /// <summary>Which idle sessions to include (0 none, 1 open-tran only, 2 all).</summary>
    [Parameter(Position = 7)]
    [ValidateRange(0, 255)]
    public int ShowSleepingSpids { get; set; }

    /// <summary>Retrieve the full batch/procedure text, not just the current statement.</summary>
    [Parameter]
    public SwitchParameter GetFullInnerText { get; set; }

    /// <summary>Retrieve execution plans (1 current statement, 2 whole batch).</summary>
    [Parameter(Position = 8)]
    [ValidateRange(0, 255)]
    public int GetPlans { get; set; }

    /// <summary>Capture the original command that initiated the current batch.</summary>
    [Parameter]
    public SwitchParameter GetOuterCommand { get; set; }

    /// <summary>Include transaction log usage and duration information.</summary>
    [Parameter]
    public SwitchParameter GetTransactionInfo { get; set; }

    /// <summary>Task and wait information collection level (0 none, 1 light, 2 full).</summary>
    [Parameter(Position = 9)]
    [ValidateRange(0, 2)]
    public int GetTaskInfo { get; set; }

    /// <summary>Retrieve detailed lock information for each session (XML).</summary>
    [Parameter]
    public SwitchParameter GetLocks { get; set; }

    /// <summary>Calculate the average execution time for the running query.</summary>
    [Parameter]
    public SwitchParameter GetAverageTime { get; set; }

    /// <summary>Include session configuration details (ANSI settings, isolation level, etc.).</summary>
    [Parameter]
    public SwitchParameter GetAdditonalInfo { get; set; }

    /// <summary>Identify the root blocking sessions and count who each is blocking.</summary>
    [Parameter]
    public SwitchParameter FindBlockLeaders { get; set; }

    /// <summary>Capture metrics at two points separated by this interval (seconds) for rate-of-change data.</summary>
    [Parameter(Position = 10)]
    [ValidateRange(0, 255)]
    public int DeltaInterval { get; set; }

    /// <summary>Which columns to include and their display order (bracket-delimited).</summary>
    [Parameter(Position = 11)]
    [ValidateLength(0, 8000)]
    [PsStringCast]
    public string OutputColumnList { get; set; } = "[dd%][session_id][sql_text][sql_command][login_name][wait_info][tasks][tran_log%][cpu%][temp%][block%][reads%][writes%][context%][physical%][query_plan][locks][%]";

    /// <summary>How results are sorted (bracket-delimited names with optional ASC/DESC).</summary>
    [Parameter(Position = 12)]
    [ValidateLength(0, 500)]
    [PsStringCast]
    public string SortOrder { get; set; } = "[start_time] ASC";

    /// <summary>Output formatting (0 none, 1 variable-width, 2 fixed-width).</summary>
    [Parameter(Position = 13)]
    [ValidateRange(0, 255)]
    public int FormatOutput { get; set; } = 1;

    /// <summary>Insert results into an existing table instead of returning them.</summary>
    [Parameter(Position = 14)]
    [ValidateLength(0, 4000)]
    [PsStringCast]
    public string DestinationTable { get; set; } = "";

    /// <summary>Return a CREATE TABLE statement for the -DestinationTable schema instead of collecting data.</summary>
    [Parameter]
    public SwitchParameter ReturnSchema { get; set; }

    /// <summary>Alternative name for -ReturnSchema.</summary>
    [Parameter(Position = 15)]
    [PsStringCast]
    public string? Schema { get; set; }

    /// <summary>Return sp_WhoIsActive parameter help instead of executing the procedure.</summary>
    [Parameter]
    public SwitchParameter Help { get; set; }

    /// <summary>The PowerShell output format (DataSet, DataTable, DataRow, PSObject).</summary>
    [Parameter(Position = 16)]
    [ValidateSet("DataSet", "DataTable", "DataRow", "PSObject")]
    [PsStringCast]
    public string As { get; set; } = "DataRow";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // The caller's $PSBoundParameters cannot be read inside the module scope; the source begin block
        // derives $passedParams and $localParams from it, so this cmdlet's own bound-parameter set is cloned
        // and threaded in as $__bound. Command-line parameters (every sp_WhoIsActive feature flag) are already
        // bound before the first record, exactly as the source begin block saw them.
        Hashtable bound = new Hashtable(MyInvocation.BoundParameters);

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
            SqlInstance, SqlCredential, Database, As, EnableException.ToBool(), bound,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block folded ahead of the process block (see class summary), with $psboundparameters ->
    // the carried $__bound dictionary. The process body is VERBATIM apart from -FunctionName
    // Invoke-DbaWhoIsActive on the direct Stop-Function / Write-Message calls. The advanced function's
    // [CmdletBinding()] declares no SupportsShouldProcess and the body never calls ShouldProcess, so the
    // compiled cmdlet likewise omits it.
    private const string BodyScript = """
param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string]$Database, [string]$As, $EnableException, $__bound, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string]$Database, [string]$As, $EnableException, $__bound)

    $passedParams = $__bound.Keys | Where-Object { 'Silent', 'SqlServer', 'SqlCredential', 'OutputAs', 'ServerInstance', 'SqlInstance', 'Database' -notcontains $_ }
    $localParams = $__bound

    # The procedure sp_WhoIsActive uses only lowercase values, so we convert the input in case we have a case sensitive database.
    if ($localParams.FilterType) { $localParams.FilterType = $localParams.FilterType.ToLower() }
    if ($localParams.NotFilterType) { $localParams.NotFilterType = $localParams.NotFilterType.ToLower() }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -MinimumVersion 9
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaWhoIsActive
        }

        $paramDictionary = @{
            Filter             = '@filter'
            FilterType         = '@filter_type'
            NotFilter          = '@not_filter'
            NotFilterType      = '@not_filter_type'
            ShowOwnSpid        = '@show_own_spid'
            ShowSystemSpids    = '@show_system_spids'
            ShowSleepingSpids  = '@show_sleeping_spids'
            GetFullInnerText   = '@get_full_inner_text'
            GetPlans           = '@get_plans'
            GetOuterCommand    = '@get_outer_command'
            GetTransactionInfo = '@get_transaction_info'
            GetTaskInfo        = '@get_task_info'
            GetLocks           = '@get_locks '
            GetAverageTime     = '@get_avg_time'
            GetAdditonalInfo   = '@get_additional_info'
            FindBlockLeaders   = '@find_block_leaders'
            DeltaInterval      = '@delta_interval'
            OutputColumnList   = '@output_column_list'
            SortOrder          = '@sort_order'
            FormatOutput       = '@format_output '
            DestinationTable   = '@destination_table '
            ReturnSchema       = '@return_schema'
            Schema             = '@schema'
            Help               = '@help'
        }

        Write-Message -Level Verbose -Message "Collecting sp_whoisactive data from server: $instance" -FunctionName Invoke-DbaWhoIsActive -ModuleName "dbatools"
        try {
            $sqlParameter = @{ }
            foreach ($param in $passedParams) {
                Write-Message -Level Verbose -Message "Check parameter '$param'" -FunctionName Invoke-DbaWhoIsActive -ModuleName "dbatools"
                $sqlParam = $paramDictionary[$param]
                if ($sqlParam) {
                    $value = $localParams[$param]
                    switch ($value) {
                        $true { $value = 1 }
                        $false { $value = 0 }
                    }
                    Write-Message -Level Verbose -Message "Adding parameter '$sqlParam' with value '$value'" -FunctionName Invoke-DbaWhoIsActive -ModuleName "dbatools"
                    $sqlParameter[$sqlParam] = $value
                }
            }
            Invoke-DbaQuery -SqlInstance $server -Query "dbo.sp_WhoIsActive" -CommandType "StoredProcedure" -SqlParameter $sqlParameter -As $As -EnableException
        } catch {
            if ($_.Exception.InnerException -Like "*Could not find*") {
                Stop-Function -Message "sp_whoisactive not found, please install using Install-DbaWhoIsActive." -Continue -FunctionName Invoke-DbaWhoIsActive
            } else {
                Stop-Function -Message "Invalid query." -Continue -FunctionName Invoke-DbaWhoIsActive
            }
        }
    }
} $SqlInstance $SqlCredential $Database $As $EnableException $__bound @__commonParameters 3>&1 2>&1
""";
}

#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Captures active client-login activity and writes it to a central table. Port of
/// public/Watch-DbaDbLogin.ps1 (W1-136). The complete per-record body rides an advanced
/// module-scoped PowerShell hop so private helpers, SMO/ETS behavior, DMV result shaping,
/// filtering, conversion, the database write pipeline, test mocks, and streams retain the
/// function's engine semantics. Surface pinned by
/// migration/baselines/Watch-DbaDbLogin.json.
/// </summary>
[Cmdlet(VerbsCommon.Watch, "DbaDbLogin", DefaultParameterSetName = "Default")]
public sealed class WatchDbaDbLoginCommand : DbaBaseCmdlet
{
    private readonly List<WarningRecord> _pendingHopWarnings = new List<WarningRecord>();

    /// <summary>SQL Server instance that stores the captured login activity.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Alternative SQL credential.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Destination database.</summary>
    [Parameter(Position = 2)]
    public string? Database { get; set; }

    /// <summary>Destination table.</summary>
    [Parameter(Position = 3)]
    public string? Table { get; set; } = "DbaTools-WatchDbLogins";

    /// <summary>Central Management Server used to discover monitored instances.</summary>
    [Parameter(Position = 4)]
    public string? SqlCms { get; set; }

    /// <summary>Text file containing monitored instances.</summary>
    [Parameter(Position = 5)]
    public string? ServersFromFile { get; set; }

    /// <summary>Pre-connected SQL Server instances to monitor.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public Microsoft.SqlServer.Management.Smo.Server[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            PSPropertyInfo? warningProperty = item?.Properties["__dbatoolsHopWarning"];
            object? warningValue = warningProperty?.Value;
            if (warningValue is PSObject wrappedWarning)
                warningValue = wrappedWarning.BaseObject;
            if (warningValue is WarningRecord hopWarning)
            {
                _pendingHopWarnings.Add(hopWarning);
                return;
            }

            PSPropertyInfo? failureProperty = item?.Properties["__dbatoolsHopFailure"];
            object? failureValue = failureProperty?.Value;
            if (failureValue is PSObject wrappedFailure)
                failureValue = wrappedFailure.BaseObject;
            if (failureValue is ErrorRecord hopError)
            {
                // DEFER to the host frame - do NOT act here. onOutput is invoked from the
                // nested pipeline's DataAdded handler (Support/NestedCommand.cs:247), so this
                // code runs on the nested pipeline's thread, inside a transient scope that is
                // discarded on unwind. Doing the work inline broke both regression tests:
                //   * PersistSuppressedWarnings' Set-Variable (:152) dot-sources into the
                //     engine's CURRENT scope, which here is the nested pipeline's, not the
                //     caller's - so the caller's -WarningVariable was never set.
                //   * the rethrow was raised INTO the pipeline still being drained, escaping
                //     DataAdded (which only catches PipelineStoppedException) into
                //     InvokeScopedStreaming's own wrapper catch, which emits a termination
                //     marker that re-enters DataAdded - a re-entrant loop that walks the script
                //     call depth to the 1000-frame limit ("call depth overflow").
                // Capture here, act after Invoke returns. Same shape Export-DbaDiagnosticQuery
                // uses (:84-94) and the one InvokeScopedStreaming itself uses for its own
                // terminating error (marker -> post-Invoke rethrow on the host frame).
                _hopFailure = hopError;
                _hopWarningPayload = item?.Properties["__dbatoolsHopWarnings"]?.Value;
                return;
            }
            else if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, Table, SqlCms, ServersFromFile, InputObject,
            EnableException.ToBool(), TestBound("SqlCms"), TestBound("ServersFromFile"),
            TestBound("InputObject"), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));

        // The nested pipeline has fully unwound; we are back on the host frame, where
        // Set-Variable reaches the caller's scope and a throw is not re-entrant.
        if (_hopFailure is not null)
        {
            ErrorRecord hopError = _hopFailure;
            _hopFailure = null;
            PersistHopWarnings(_hopWarningPayload);
            _hopWarningPayload = null;
            NestedCommand.RemoveDuplicateError(this, hopError);
            // Keep RethrowScript/InvokeScoped rather than ThrowTerminatingError: `throw $record`
            // preserves the record's FullyQualifiedErrorId verbatim, which the suite asserts
            // exactly (tests/Watch-DbaDbLogin.Tests.ps1:113 wants "dbatools_Watch-DbaDbLogin");
            // ThrowTerminatingError would append the cmdlet identity and break it.
            _ = NestedCommand.InvokeScoped(this, RethrowScript, hopError);
        }
    }

    // Set only from inside the streaming callback, consumed only on the host frame.
    private ErrorRecord? _hopFailure;
    private object? _hopWarningPayload;

    private void PersistHopWarnings(object? warnings)
    {
        List<WarningRecord> collected = new List<WarningRecord>(_pendingHopWarnings);
        _pendingHopWarnings.Clear();

        if (warnings is not null)
        {
            IEnumerable? warningItems = LanguagePrimitives.GetEnumerable(warnings);
            if (warningItems is null)
            {
                object? single = warnings is PSObject wrapped ? wrapped.BaseObject : warnings;
                if (single is WarningRecord warning)
                    collected.Add(warning);
            }
            else
            {
                foreach (object? item in warningItems)
                {
                    object? unwrapped = item is PSObject wrapped ? wrapped.BaseObject : item;
                    if (unwrapped is WarningRecord warning)
                        collected.Add(warning);
                }
            }
        }

        HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
        List<WarningRecord> unique = new List<WarningRecord>();
        foreach (WarningRecord warning in collected)
        {
            if (seen.Add(warning.Message))
                unique.Add(warning);
        }
        PersistSuppressedWarnings(unique);
    }

    private void PersistSuppressedWarnings(IList<WarningRecord> warnings)
    {
        if (warnings.Count == 0)
            return;
        if (!MyInvocation.BoundParameters.TryGetValue("WarningVariable", out object? rawName))
            return;

        string variableName = LanguagePrimitives.ConvertTo<string>(rawName);
        bool append = variableName.StartsWith("+", StringComparison.Ordinal);
        if (append)
            variableName = variableName.Substring(1);
        if (String.IsNullOrWhiteSpace(variableName))
            return;

        ScriptBlock persistScript = ScriptBlock.Create("""
param($__name, $__warnings, $__append)
$__items = @()
if ($__append) {
    $__items = @(Get-Variable -Name $__name -ValueOnly -ErrorAction SilentlyContinue)
}
$__items += @($__warnings)
Set-Variable -Name $__name -Value $__items
""");
        _ = InvokeCommand.InvokeScript(false, persistScript, null, variableName, (object)warnings, append);
    }

    private const string RethrowScript = """
param($Record)
throw $Record
""";

    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Table, $SqlCms, $ServersFromFile, $InputObject, $EnableException, $__boundSqlCms, $__boundServersFromFile, $__boundInputObject, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
$__automaticHopWarnings = @()
try {
& $__dbatoolsModule {
    [CmdletBinding()]
    param($SqlInstance, $SqlCredential, $Database, $Table, $SqlCms, $ServersFromFile, [Microsoft.SqlServer.Management.Smo.Server[]]$InputObject, $EnableException, $__boundSqlCms, $__boundServersFromFile, $__boundInputObject)

        $__invokeConnect = {
            [CmdletBinding()]
            param([hashtable]$Parameters)
            Connect-DbaInstance @Parameters
        }
        $__getConnectWarning = {
            param($Warnings, [datetime]$Started, $Target, $ErrorRecord)
            $__warningRecord = $null
            if (@($Warnings).Count -gt 0) {
                $__warningRecord = @($Warnings)[-1]
            } else {
                $__entry = Get-DbatoolsLog |
                    Where-Object { $_.FunctionName -eq "Connect-DbaInstance" -and $_.Timestamp -ge $Started -and [int]$_.Level -eq 666 } |
                    Select-Object -Last 1
                if ($__entry) {
                    $__warningRecord = [System.Management.Automation.WarningRecord]::new(
                        ("[{0:HH:mm:ss}][{1}] {2}" -f $__entry.Timestamp, $__entry.FunctionName, $__entry.Message))
                } else {
                    $__warningRecord = [System.Management.Automation.WarningRecord]::new(
                        ("[{0:HH:mm:ss}][Connect-DbaInstance] Failure | Error connecting to [{1}]: {2}" -f (Get-Date), $Target, $ErrorRecord.Exception.Message))
                }
            }
            if ($__warningRecord) {
                if ($EnableException) {
                    [pscustomobject]@{ __dbatoolsHopWarning = $__warningRecord }
                } else {
                    Write-Warning $__warningRecord.Message
                }
            }
        }

        if (-not ($__boundSqlCms -or $__boundServersFromFile -or $__boundInputObject)) {
            Stop-Function -Message "You must specify a server list source using -SqlCms or -ServersFromFile or pipe in connected instances. See the command documentation and examples for more details." -FunctionName Watch-DbaDbLogin
            return
        }

        try {
            $__connectWarnings = @()
            $__connectStarted = Get-Date
            $serverDest = & $__invokeConnect @{
                SqlInstance = $SqlInstance
                SqlCredential = $SqlCredential
            } -WarningVariable __connectWarnings
        } catch {
            & $__getConnectWarning $__connectWarnings $__connectStarted $SqlInstance $_
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -FunctionName Watch-DbaDbLogin
            return
        }

        $systemdbs = "master", "msdb", "model", "tempdb"
        $excludedPrograms = "Microsoft SQL Server Management Studio - Query", "SQL Management"

        <#
            Get servers to query from Central Management Server or File
        #>
        if ($SqlCms) {
            try {
                $servers = Get-DbaRegServer -SqlInstance $SqlCms -SqlCredential $SqlCredential -EnableException
            } catch {
                Stop-Function -Message "The CMS server, $SqlCms, was not accessible." -Target $SqlCms -ErrorRecord $_ -FunctionName Watch-DbaDbLogin
                return
            }
        }
        if ($ServersFromFile) {
            if (Test-Path $ServersFromFile) {
                $servers = Get-Content $ServersFromFile
            } else {
                Stop-Function -Message "$ServersFromFile was not found." -Target $ServersFromFile -FunctionName Watch-DbaDbLogin
                return
            }
        }

        <#
            Connect each server
        #>
        foreach ($instance in $servers) {
            try {
                $__connectWarnings = @()
                $__connectStarted = Get-Date
                if ($instance -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer]) {
                    $__sourceInstance = $instance.ServerName
                } else {
                    $__sourceInstance = $instance
                }
                $InputObject += & $__invokeConnect @{
                    SqlInstance = $__sourceInstance
                    SqlCredential = $SqlCredential
                    MinimumVersion = 9
                } -WarningVariable __connectWarnings
            } catch {
                & $__getConnectWarning $__connectWarnings $__connectStarted $__sourceInstance $_
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Watch-DbaDbLogin
            }
        }

        <#
            Process each server
        #>
        foreach ($instance in $InputObject) {

            if (-not (Test-SqlSa $instance)) {
                Write-Message -Level Warning -Message "Not a sysadmin on $instance, resultset would be underwhelming. Skipping." -FunctionName Watch-DbaDbLogin -ModuleName "dbatools";
                continue
            }

            if ($instance.VersionMajor -le 10) {
                $sql = "
                SELECT
                    s.login_time AS [LoginTime]
                    , s.login_name AS [Login]
                    , ISNULL(s.host_name,N'') AS [Host]
                    , ISNULL(s.program_name,N'') AS [Program]
                    , ISNULL(r.database_id,N'') AS [DatabaseId]
                    , ISNULL(DB_NAME(r.database_id),N'') AS [Database]
                    , CAST(~s.is_user_process AS BIT) AS [IsSystem]
                    , CaptureTime = (SELECT GETDATE())
                FROM sys.dm_exec_sessions AS s
                LEFT OUTER JOIN sys.dm_exec_requests AS r
                    ON r.session_id = s.session_id"
            } else {
                $sql = "
                SELECT
                    s.login_time AS [LoginTime]
                    , s.login_name AS [Login]
                    , ISNULL(s.host_name,N'') AS [Host]
                    , ISNULL(s.program_name,N'') AS [Program]
                    , ISNULL(r.database_id,s.database_id) AS [DatabaseId]
                    , ISNULL(DB_NAME(r.database_id),(DB_NAME(s.database_id))) AS [Database]
                    , CAST(~s.is_user_process AS BIT) AS [IsSystem]
                    , CaptureTime = (SELECT GETDATE())
                    ,s.database_id
                    FROM sys.dm_exec_sessions AS s
                    LEFT OUTER JOIN sys.dm_exec_requests AS r
                    ON r.session_id = s.session_id"
            }

            Write-Message -Level Debug -Message $sql -FunctionName Watch-DbaDbLogin -ModuleName "dbatools"

            $procs = $instance.Query($sql) | Where-Object { $_.Host -ne $instance.ComputerName -and ![string]::IsNullOrEmpty($_.Host) }
            $procs = $procs | Where-Object { $systemdbs -notcontains $_.Database -and $excludedPrograms -notcontains $_.Program }

            if ($procs.Count -gt 0) {
                $procs | Select-Object @{Label = "ComputerName"; Expression = { $instance.ComputerName } }, @{Label = "InstanceName"; Expression = { $instance.ServiceName } }, @{Label = "SqlInstance"; Expression = { $instance.DomainInstanceName } }, LoginTime, Login, Host, Program, DatabaseId, Database, IsSystem, CaptureTime | ConvertTo-DbaDataTable | Write-DbaDbTableData -SqlInstance $serverDest -Database $Database -Table $Table -AutoCreateTable

                Write-Message -Level Output -Message "Added process information for $instance to datatable." -FunctionName Watch-DbaDbLogin -ModuleName "dbatools"
            } else {
                Write-Message -Level Verbose -Message "No data returned for $instance." -FunctionName Watch-DbaDbLogin -ModuleName "dbatools"
            }
        }

} $SqlInstance $SqlCredential $Database $Table $SqlCms $ServersFromFile $InputObject $EnableException $__boundSqlCms $__boundServersFromFile $__boundInputObject @__commonParameters -WarningVariable __automaticHopWarnings 3>&1 2>&1
} catch {
    [pscustomobject]@{
        __dbatoolsHopFailure = $_
        __dbatoolsHopWarnings = @($__automaticHopWarnings)
    }
}
""";
}

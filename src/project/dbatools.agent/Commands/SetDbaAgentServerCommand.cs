#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoJobServer = Microsoft.SqlServer.Management.Smo.Agent.JobServer;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Configures SQL Server Agent service properties and operational settings.
/// </summary>
/// <remarks>
/// The mail-type/log-level normalization, the history-row validation, the instance connection, the
/// JobServer property assignments, the Alter, and the output all run the original dbatools PowerShell body
/// inside the dbatools module scope rather than being reimplemented in C#, so the engine decides the
/// observable details.
///
/// The function has begin/process/end blocks. The begin block runs one-shot MaximumHistoryRows /
/// MaximumJobHistoryRows validations whose no-Continue Stop-Functions set the function-scope interrupt and
/// return; every process record then short-circuits via Test-FunctionInterrupt. That interrupt does not
/// survive between hops (Stop-Function writes it at -Scope 1 of the begin hop's own scriptblock), so the
/// begin hop reads it with Get-Variable -Scope 0 after a dot-sourced body and reports it in a sentinel; the
/// C# field then guards ProcessRecord. The process block ALSO sets the interrupt (its own no-Continue
/// "must specify instance" guard), so the process hop re-reports it too. Under -EnableException those
/// Stop-Functions throw instead, terminating the record. The end block (a bare Verbose line) runs even after
/// a non-EnableException interrupt, so EndProcessing is guarded ONLY by the C# stop flag, NOT by the
/// interrupt.
///
/// The begin block's AgentMailType/AgentLogLevel string-to-integer conversions are folded into the top of
/// the process hop: they are idempotent (re-running on an already-int value is a no-op) and produce no
/// output, so recomputing them per record from the original bound value equals running them once in begin.
/// $PSBoundParameters.ContainsKey(...) reads are replaced by $__bound.ContainsKey on this cmdlet's own bound
/// parameters, because inside the hop the inner scriptblock's $PSBoundParameters would show every parameter
/// as bound.
///
/// Output streams: each altered JobServer is emitted before a later one may fail under -EnableException, so
/// the process hop streams. Surface pinned by migration/baselines/Set-DbaAgentServer.json.
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaAgentServer", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class SetDbaAgentServerCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>SQL Server Agent JobServer objects piped in from Get-DbaAgentServer.</summary>
    [Parameter(Position = 2, ValueFromPipeline = true)]
    public SmoJobServer[]? InputObject { get; set; }

    /// <summary>The SQL Server Agent logging level.</summary>
    [Parameter(Position = 3)]
    [ValidateSet("1", "Errors", "2", "Warnings", "3", "Errors, Warnings", "4", "Informational", "5", "Errors, Informational", "6", "Warnings, Informational", "7", "All")]
    public object? AgentLogLevel { get; set; }

    /// <summary>Whether SQL Server Agent uses legacy SQL Agent Mail or Database Mail.</summary>
    [Parameter(Position = 4)]
    [ValidateSet("0", "SqlAgentMail", "1", "DatabaseMail")]
    public object? AgentMailType { get; set; }

    /// <summary>How long (seconds) SQL Server waits for Agent to shut down.</summary>
    [Parameter(Position = 5)]
    [ValidateRange(5, 600)]
    public int AgentShutdownWaitTime { get; set; }

    /// <summary>Which Database Mail profile SQL Server Agent uses.</summary>
    [Parameter(Position = 6)]
    public string? DatabaseMailProfile { get; set; }

    /// <summary>The file path where SQL Server Agent writes its error log.</summary>
    [Parameter(Position = 7)]
    public string? ErrorLogFile { get; set; }

    /// <summary>How long (seconds) CPU must remain below the idle threshold.</summary>
    [Parameter(Position = 8)]
    [ValidateRange(20, 86400)]
    public int IdleCpuDuration { get; set; }

    /// <summary>The CPU usage percentage threshold below which the server is idle.</summary>
    [Parameter(Position = 9)]
    [ValidateRange(10, 100)]
    public int IdleCpuPercentage { get; set; }

    /// <summary>Enables or disables CPU idle condition monitoring.</summary>
    [Parameter(Position = 10)]
    [PsStringCast]
    [ValidateSet("Enabled", "Disabled")]
    public string? CpuPolling { get; set; }

    /// <summary>An alias SQL Server Agent uses for the local server.</summary>
    [Parameter(Position = 11)]
    public string? LocalHostAlias { get; set; }

    /// <summary>The timeout (seconds) for SQL Server Agent connections.</summary>
    [Parameter(Position = 12)]
    [ValidateRange(5, 45)]
    public int LoginTimeout { get; set; }

    /// <summary>The total number of job history rows retained in MSDB.</summary>
    [Parameter(Position = 13)]
    public int MaximumHistoryRows { get; set; }

    /// <summary>The maximum number of history rows retained per individual job.</summary>
    [Parameter(Position = 14)]
    public int MaximumJobHistoryRows { get; set; }

    /// <summary>The network recipient for legacy net send notifications.</summary>
    [Parameter(Position = 15)]
    public string? NetSendRecipient { get; set; }

    /// <summary>Whether SQL Server Agent replaces tokens in alert messages.</summary>
    [Parameter(Position = 16)]
    [PsStringCast]
    [ValidateSet("Enabled", "Disabled")]
    public string? ReplaceAlertTokens { get; set; }

    /// <summary>Whether copies of agent notification emails are saved to sent items.</summary>
    [Parameter(Position = 17)]
    [PsStringCast]
    [ValidateSet("Enabled", "Disabled")]
    public string? SaveInSentFolder { get; set; }

    /// <summary>Whether SQL Server Agent starts automatically when SQL Server starts.</summary>
    [Parameter(Position = 18)]
    [PsStringCast]
    [ValidateSet("Enabled", "Disabled")]
    public string? SqlAgentAutoStart { get; set; }

    /// <summary>The legacy SQL Agent Mail profile for notifications.</summary>
    [Parameter(Position = 19)]
    public string? SqlAgentMailProfile { get; set; }

    /// <summary>Whether SQL Server Agent automatically restarts if it stops unexpectedly.</summary>
    [Parameter(Position = 20)]
    [PsStringCast]
    [ValidateSet("Enabled", "Disabled")]
    public string? SqlAgentRestart { get; set; }

    /// <summary>Whether SQL Server Agent can restart the SQL Server service.</summary>
    [Parameter(Position = 21)]
    [PsStringCast]
    [ValidateSet("Enabled", "Disabled")]
    public string? SqlServerRestart { get; set; }

    /// <summary>Whether SQL Server Agent writes errors to the Windows Application Event Log.</summary>
    [Parameter(Position = 22)]
    [PsStringCast]
    [ValidateSet("Enabled", "Disabled")]
    public string? WriteOemErrorLog { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which the
    // inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    // The function-scope interrupt set by the begin validations and the process "must specify" guard.
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            MaximumHistoryRows, MaximumJobHistoryRows, EnableException.ToBool(),
            new Hashtable(MyInvocation.BoundParameters),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__setDbaAgentServerBegin"))
            {
                if (sentinel["__setDbaAgentServerBegin"] is Hashtable state)
                {
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                }
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
        if (Interrupted || _interrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__setDbaAgentServerProcess"))
            {
                if (sentinel["__setDbaAgentServerProcess"] is Hashtable state)
                {
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                }
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, InputObject, AgentLogLevel, AgentMailType, AgentShutdownWaitTime,
            DatabaseMailProfile, ErrorLogFile, IdleCpuDuration, IdleCpuPercentage, CpuPolling, LocalHostAlias,
            LoginTimeout, MaximumHistoryRows, MaximumJobHistoryRows, NetSendRecipient, ReplaceAlertTokens,
            SaveInSentFolder, SqlAgentAutoStart, SqlAgentMailProfile, SqlAgentRestart, SqlServerRestart,
            WriteOemErrorLog, EnableException.ToBool(), new Hashtable(MyInvocation.BoundParameters), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
    {
        // NOT guarded by _interrupted: the source's end block runs even after a non-EnableException interrupt.
        if (Interrupted)
        {
            return;
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, EndScript,
            EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    // PS: the begin block VERBATIM apart from $PSBoundParameters.ContainsKey -> $__bound.ContainsKey and
    // -FunctionName Set-DbaAgentServer on the direct Stop-Function sites. The AgentMailType/AgentLogLevel
    // conversions are folded into the process hop (idempotent, no output). Dot-sourced so the guard returns
    // still emit the interrupt sentinel.
    private const string BeginScript = """
param($MaximumHistoryRows, $MaximumJobHistoryRows, $EnableException, $__bound, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([int]$MaximumHistoryRows, [int]$MaximumJobHistoryRows, $EnableException, $__bound)
    . {
        if ($__bound.ContainsKey("MaximumHistoryRows") -and ($MaximumHistoryRows -ne -1 -and $MaximumHistoryRows -notin 2..999999)) {
            Stop-Function -Message "You must specify a MaximumHistoryRows value of -1 (i.e. turn off max history) or a value between 2 and 999999. See the command description for examples." -FunctionName Set-DbaAgentServer
            return
        }

        if ($__bound.ContainsKey("MaximumJobHistoryRows") -and ($MaximumJobHistoryRows -ne 0 -and $MaximumJobHistoryRows -notin 2..999999)) {
            Stop-Function -Message "You must specify a MaximumJobHistoryRows value of 0 (i.e. turn off max history) or a value between 2 and 999999. See the command description for examples." -FunctionName Set-DbaAgentServer
            return
        }
    }
    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __setDbaAgentServerBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $MaximumHistoryRows $MaximumJobHistoryRows $EnableException $__bound @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM apart from $PSCmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess,
    // $PSBoundParameters.ContainsKey -> $__bound.ContainsKey, and -FunctionName Set-DbaAgentServer on the
    // direct Stop-Function/Write-Message sites. The begin's AgentMailType/AgentLogLevel conversions are
    // prepended (folded from begin). The body is dot-sourced so the Test-FunctionInterrupt / "must specify"
    // returns exit only the block; the interrupt flag is then read and reported in a sentinel.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $InputObject, $AgentLogLevel, $AgentMailType, $AgentShutdownWaitTime, $DatabaseMailProfile, $ErrorLogFile, $IdleCpuDuration, $IdleCpuPercentage, $CpuPolling, $LocalHostAlias, $LoginTimeout, $MaximumHistoryRows, $MaximumJobHistoryRows, $NetSendRecipient, $ReplaceAlertTokens, $SaveInSentFolder, $SqlAgentAutoStart, $SqlAgentMailProfile, $SqlAgentRestart, $SqlServerRestart, $WriteOemErrorLog, $EnableException, $__bound, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [Microsoft.SqlServer.Management.Smo.Agent.JobServer[]]$InputObject, [object]$AgentLogLevel, [object]$AgentMailType, [int]$AgentShutdownWaitTime, [string]$DatabaseMailProfile, [string]$ErrorLogFile, [int]$IdleCpuDuration, [int]$IdleCpuPercentage, [string]$CpuPolling, [string]$LocalHostAlias, [int]$LoginTimeout, [int]$MaximumHistoryRows, [int]$MaximumJobHistoryRows, [string]$NetSendRecipient, [string]$ReplaceAlertTokens, [string]$SaveInSentFolder, [string]$SqlAgentAutoStart, [string]$SqlAgentMailProfile, [string]$SqlAgentRestart, [string]$SqlServerRestart, [string]$WriteOemErrorLog, $EnableException, $__bound, $__realCmdlet)
    # Check of the agent mail type is of type string and set the integer value
    if (($AgentMailType -notin 0, 1) -and ($null -ne $AgentMailType)) {
        $AgentMailType = switch ($AgentMailType) { "SqlAgentMail" { 0 } "DatabaseMail" { 1 } }
    }

    # Check of the agent log level is of type string and set the integer value
    if (($AgentLogLevel -notin 0, 1) -and ($null -ne $AgentLogLevel)) {
        $AgentLogLevel = switch ($AgentLogLevel) { "Errors" { 1 } "Warnings" { 2 } "Errors, Warnings" { 3 } "Informational" { 4 } "Errors, Informational" { 5 } "Warnings, Informational" { 6 } "All" { 7 } }
    }

    . {
        if (Test-FunctionInterrupt) { return }

        if ((-not $InputObject) -and (-not $SqlInstance)) {
            Stop-Function -Message "You must specify an Instance or pipe in results from another command" -Target $SqlInstance -FunctionName Set-DbaAgentServer
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaAgentServer
            }

            $server.JobServer.Refresh()
            $InputObject += $server.JobServer
        }

        foreach ($jobServer in $InputObject) {
            $server = $jobServer.Parent

            #region job server options
            # Settings the options for the job server
            if ($AgentLogLevel) {
                Write-Message -Message "Setting Agent log level to $AgentLogLevel" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.AgentLogLevel = $AgentLogLevel
            }

            if ($AgentMailType) {
                Write-Message -Message "Setting Agent Mail Type to $AgentMailType" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.AgentMailType = $AgentMailType
            }

            if ($AgentShutdownWaitTime) {
                Write-Message -Message "Setting Agent Shutdown Wait Time to $AgentShutdownWaitTime" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.AgentShutdownWaitTime = $AgentShutdownWaitTime
            }

            if ($DatabaseMailProfile) {
                if ($DatabaseMailProfile -in (Get-DbaDbMail -SqlInstance $server).Profiles.Name) {
                    Write-Message -Message "Setting Database Mail Profile to $DatabaseMailProfile" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                    $jobServer.DatabaseMailProfile = $DatabaseMailProfile
                } else {
                    Write-Message -Message "Database mail profile not found on $server" -Level Warning -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                }
            }

            if ($ErrorLogFile) {
                Write-Message -Message "Setting agent server ErrorLogFile to $ErrorLogFile" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.ErrorLogFile = $ErrorLogFile
            }

            if ($IdleCpuDuration) {
                Write-Message -Message "Setting agent server IdleCpuDuration to $IdleCpuDuration" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.IdleCpuDuration = $IdleCpuDuration
            }

            if ($IdleCpuPercentage) {
                Write-Message -Message "Setting agent server IdleCpuPercentage to $IdleCpuPercentage" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.IdleCpuPercentage = $IdleCpuPercentage
            }

            if ($CpuPolling) {
                Write-Message -Message "Setting agent server IsCpuPollingEnabled to $IsCpuPollingEnabled" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.IsCpuPollingEnabled = if ($CpuPolling -eq "Enabled") { $true } else { $false }
            }

            if ($LocalHostAlias) {
                Write-Message -Message "Setting agent server LocalHostAlias to $LocalHostAlias" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.LocalHostAlias = $LocalHostAlias
            }

            if ($LoginTimeout) {
                Write-Message -Message "Setting agent server LoginTimeout to $LoginTimeout" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.LoginTimeout = $LoginTimeout
            }

            if ($MaximumHistoryRows) {
                Write-Message -Message "Setting agent server MaximumHistoryRows to $MaximumHistoryRows" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.MaximumHistoryRows = $MaximumHistoryRows
            }

            if ($__bound.ContainsKey("MaximumJobHistoryRows")) {
                Write-Message -Message "Setting agent server MaximumJobHistoryRows to $MaximumJobHistoryRows" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.MaximumJobHistoryRows = $MaximumJobHistoryRows
            }

            if ($NetSendRecipient) {
                Write-Message -Message "Setting agent server NetSendRecipient to $NetSendRecipient" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.NetSendRecipient = $NetSendRecipient
            }

            if ($ReplaceAlertTokens) {
                Write-Message -Message "Setting agent server ReplaceAlertTokensEnabled to $ReplaceAlertTokens" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.ReplaceAlertTokensEnabled = if ($ReplaceAlertTokens -eq "Enabled") { $true } else { $false }
            }

            if ($SaveInSentFolder) {
                Write-Message -Message "Setting agent server SaveInSentFolder to $SaveInSentFolder" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.SaveInSentFolder = if ($SaveInSentFolder -eq "Enabled") { $true } else { $false }
            }

            if ($SqlAgentAutoStart) {
                Write-Message -Message "Setting agent server SqlAgentAutoStart to $SqlAgentAutoStart" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.SqlAgentAutoStart = if ($SqlAgentAutoStart -eq "Enabled") { $true } else { $false }
            }

            if ($SqlAgentMailProfile) {
                Write-Message -Message "Setting agent server SqlAgentMailProfile to $SqlAgentMailProfile" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.SqlAgentMailProfile = $SqlAgentMailProfile
            }

            if ($SqlAgentRestart) {
                Write-Message -Message "Setting agent server SqlAgentRestart to $SqlAgentRestart" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.SqlAgentRestart = if ($SqlAgentRestart -eq "Enabled") { $true } else { $false }
            }

            if ($SqlServerRestart) {
                Write-Message -Message "Setting agent server SqlServerRestart to $SqlServerRestart" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.SqlServerRestart = if ($SqlServerRestart -eq "Enabled") { $true } else { $false }
            }

            if ($WriteOemErrorLog) {
                Write-Message -Message "Setting agent server WriteOemErrorLog to $WriteOemErrorLog" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
                $jobServer.WriteOemErrorLog = if ($WriteOemErrorLog -eq "Enabled") { $true } else { $false }
            }

            #endregion server agent options

            # Execute
            if ($__realCmdlet.ShouldProcess($SqlInstance, "Changing the agent server")) {
                try {
                    Write-Message -Message "Changing the agent server" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"

                    # Change the agent server
                    $jobServer.Alter()
                } catch {
                    Stop-Function -Message "Something went wrong changing the agent server" -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaAgentServer
                }

                Get-DbaAgentServer -SqlInstance $server | Where-Object Name -eq $jobServer.name
            }
        }
    }
    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __setDbaAgentServerProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $SqlInstance $SqlCredential $InputObject $AgentLogLevel $AgentMailType $AgentShutdownWaitTime $DatabaseMailProfile $ErrorLogFile $IdleCpuDuration $IdleCpuPercentage $CpuPolling $LocalHostAlias $LoginTimeout $MaximumHistoryRows $MaximumJobHistoryRows $NetSendRecipient $ReplaceAlertTokens $SaveInSentFolder $SqlAgentAutoStart $SqlAgentMailProfile $SqlAgentRestart $SqlServerRestart $WriteOemErrorLog $EnableException $__bound $__realCmdlet @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM apart from -FunctionName Set-DbaAgentServer on the direct Write-Message.
    // $EnableException is marshaled in so Write-Message's scope-walking default has it + to give the hop a
    // positional arg.
    private const string EndScript = """
param($EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($EnableException)
    Write-Message -Message "Finished changing agent server(s)" -Level Verbose -FunctionName Set-DbaAgentServer -ModuleName "dbatools"
} $EnableException @__commonParameters 3>&1 2>&1
""";
}

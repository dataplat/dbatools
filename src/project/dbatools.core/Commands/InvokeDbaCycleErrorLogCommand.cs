#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Cycles the SQL Server (and/or Agent) error log. Port of public/Invoke-DbaCycleErrorLog.ps1
/// (W3-059). The begin block computes $sql and $logToCycle from the call-constant -Type parameter (a
/// deterministic switch), so inlining it into the process script recomputes the identical values each
/// record - no cross-record carry, no sentinel needed. DEF-001 cond1+cond2: the process foreach EMITS
/// a [PSCustomObject] per instance (success and failure branches) AND has reachable Stop-Function
/// -Continue at Connect-DbaInstance and the query catch, so the hop STREAMS via InvokeScopedStreaming.
/// The source's Test-Bound 'Type' guard is carried as a bound flag (the guard is effectively dead
/// given the ValidateSet, but preserved verbatim). Positions match the retired function (SqlInstance=0,
/// SqlCredential=1, Type=2; EnableException=switch/null) and Type's ValidateSet (instance/agent) is
/// preserved. Substitutions only: Test-Bound -> the carried $__boundType flag, $Pscmdlet.ShouldProcess
/// -> $__realCmdlet.ShouldProcess (ConfirmImpact LOW mirrored), explicit -FunctionName
/// Invoke-DbaCycleErrorLog on Stop-Function (W1-090); the body is otherwise verbatim. Surface pinned by
/// migration/baselines/Invoke-DbaCycleErrorLog.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaCycleErrorLog", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class InvokeDbaCycleErrorLogCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Which error log to cycle: 'instance', 'agent', or both when omitted.</summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    [ValidateSet("instance", "agent")]
    public string? Type { get; set; }

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
            SqlInstance, SqlCredential, Type, EnableException.ToBool(), this, TestBound(nameof(Type)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block ($sql / $logToCycle from the call-constant -Type) inlines ahead of the
    // process body, which is VERBATIM per record. Substitutions only: Test-Bound -> the carried
    // $__boundType flag, $Pscmdlet -> $__realCmdlet, explicit -FunctionName Invoke-DbaCycleErrorLog
    // on Stop-Function (W1-090).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Type, $EnableException, $__realCmdlet, $__boundType, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string]$Type, $EnableException, $__realCmdlet, $__boundType, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($__boundType) {
        if ($Type -notin 'instance', 'agent') {
            Stop-Function -Message "The type provided [$Type] for $SqlInstance is not an accepted value. Please use 'Instance' or 'Agent'" -FunctionName Invoke-DbaCycleErrorLog
            return
        }
    }
    $logToCycle = @()
    switch ($Type) {
        'agent' {
            $sql = "EXEC msdb.dbo.sp_cycle_agent_errorlog;"
            $logToCycle = $Type
        }
        'instance' {
            $sql = "EXEC master.dbo.sp_cycle_errorlog;"
            $logToCycle = $Type
        }
        default {
            $sql = "
                    EXEC master.dbo.sp_cycle_errorlog;
                    EXEC msdb.dbo.sp_cycle_agent_errorlog;"
            $logToCycle = 'instance', 'agent'
        }
    }

    if (Test-FunctionInterrupt) { return }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaCycleErrorLog
        }

        try {
            $logs = $logToCycle -join ','
            if ($__realCmdlet.ShouldProcess($server, "Cycle the log(s): $logs")) {
                $null = $server.Query($sql)
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    LogType      = $logToCycle
                    IsSuccessful = $true
                    Notes        = $null
                }
            }
        } catch {
            [PSCustomObject]@{
                ComputerName = $server.ComputerName
                InstanceName = $server.ServiceName
                SqlInstance  = $server.DomainInstanceName
                LogType      = $logToCycle
                IsSuccessful = $false
                Notes        = $_.Exception
            }
            Stop-Function -Message "Issue cycling $logs on $server" -Target $server -ErrorRecord $_ -Exception $_.Exception -Continue -FunctionName Invoke-DbaCycleErrorLog
        }
    }
} $SqlInstance $SqlCredential $Type $EnableException $__realCmdlet $__boundType $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

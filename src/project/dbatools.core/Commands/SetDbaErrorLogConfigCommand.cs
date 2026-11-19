#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets the error-log count/size on instances. Port of public/Set-DbaErrorLogConfig.ps1
/// (W3-091). PER-ELEMENT process hops - both amended-25a09f3 conditions verified: the
/// ShouldProcess gates route to the REAL cmdlet ($__realCmdlet, whose CommandRuntime
/// persists across hops AND records - no Force/ConfirmPreference convention in this
/// source, so no transplant and no template-hold exposure) and the loop body has no
/// cross-element state. VFP-LOCAL CLASSIFICATION TABLE (SqlInstance is VFPBPN):
/// $server/$currentNumLogs/$currentLogSize/$collection are all assigned unconditionally
/// at the top of every iteration = SAFE; no local crosses records; no sentinel.
/// Test-Bound -ParameterName LogSize/LogCount reads the FUNCTION's binding and rides as
/// carried C#-side TestBound flags (the W3-066/W3-090 class - the hop scriptblock has
/// no function binding to inspect). [PsIntCast] on BOTH int params (W1-043: the script
/// [int] cast converts an explicit null to 0 BEFORE ValidateRange/mandatory runs -
/// LogCount's ValidateRange(6,99) then rejects 0 with the RANGE message, not the null
/// message). The double-gate output-refresh quirk (a second ShouldProcess wrapping the
/// $server.Refresh() + collection update, so -WhatIf keeps the PRE-alter values in the
/// emitted row) and the triple-nested InnerException reach-through on the catch ride
/// verbatim. NO WarningAction carrier (codex W3-005 r3). Surface pinned by
/// migration/baselines/Set-DbaErrorLogConfig.json (implicit positions 0-3 - no sets, so
/// the function binder assigns them - SqlInstance Mandatory VFPBPN pos0, LogCount
/// ValidateRange 6-99 pos2, default ConfirmImpact Medium).
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaErrorLogConfig", SupportsShouldProcess = true)]
public sealed class SetDbaErrorLogConfigCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Mandatory = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Number of error logs to keep (6-99).</summary>
    [Parameter(Position = 2)]
    [PsIntCast]
    [ValidateRange(6, 99)]
    public int LogCount { get; set; }

    /// <summary>Maximum error-log size in KB before cycling (SQL 2012+).</summary>
    [Parameter(Position = 3)]
    [PsIntCast]
    public int LogSize { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // Stream one hop PER INSTANCE (25a09f3 as amended): real-cmdlet gates + no
        // cross-element state make this row per-element-eligible.
        foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
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
            new[] { instance }, SqlCredential, LogCount, LogSize,
                TestBound(nameof(LogCount)), TestBound(nameof(LogSize)),
                EnableException.ToBool(), this,
                NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
        }
    }

    // PS: the process loop body VERBATIM per element. Substitutions only: $PSCmdlet ->
    // $__realCmdlet on the four gates, Test-Bound -ParameterName LogSize/LogCount ->
    // the carried $__boundLogSize/$__boundLogCount flags, and explicit -FunctionName
    // Set-DbaErrorLogConfig on Stop-Function/Write-Message (W1-090). The [dbasize]
    // casts, the version guard and the triple InnerException reach-through ride as-is.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $LogCount, $LogSize, $__boundLogCount, $__boundLogSize, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [int]$LogCount, [int]$LogSize, $__boundLogCount, $__boundLogSize, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaErrorLogConfig
        }

        $currentNumLogs = $server.NumberOfLogFiles
        $currentLogSize = $server.ErrorLogSizeKb

        $collection = [PSCustomObject]@{
            ComputerName = $server.ComputerName
            InstanceName = $server.ServiceName
            SqlInstance  = $server.DomainInstanceName
            LogCount     = $currentNumLogs
            LogSize      = [dbasize]($currentLogSize * 1024)
        }
        if ($__boundLogSize) {
            if ($server.VersionMajor -lt 11) {
                Stop-Function -Message "Size is cannot be set on $instance. SQL Server 2008 R2 and below not supported." -Continue -FunctionName Set-DbaErrorLogConfig
            }
            if ($LogSize -eq $currentLogSize) {
                Write-Message -Level Warning -Message "The provided value for LogSize is already set to $LogSize KB on $instance" -FunctionName Set-DbaErrorLogConfig -ModuleName "dbatools"
            } else {
                if ($__realCmdlet.ShouldProcess($server, "Updating log size from [$currentLogSize] to [$LogSize]")) {
                    try {
                        $server.ErrorLogSizeKb = $LogSize
                        $server.Alter()
                    } catch {
                        Stop-Function -Message "Issue setting number of log files on $instance" -Target $instance -ErrorRecord $_ -Exception $_.Exception.InnerException.InnerException.InnerException -Continue -FunctionName Set-DbaErrorLogConfig
                    }
                }
                if ($__realCmdlet.ShouldProcess($server, "Output final results of setting error log size")) {
                    $server.Refresh()
                    $collection.LogSize = [dbasize]($server.ErrorLogSizeKb * 1024)
                }
            }
        }

        if ($__boundLogCount) {
            if ($LogCount -eq $currentNumLogs) {
                Write-Message -Level Warning -Message "The provided value for LogCount is already set to $LogCount on $instance" -FunctionName Set-DbaErrorLogConfig -ModuleName "dbatools"
            } else {
                if ($__realCmdlet.ShouldProcess($server, "Setting number of logs from [$currentNumLogs] to [$LogCount]")) {
                    try {
                        $server.NumberOfLogFiles = $LogCount
                        $server.Alter()
                    } catch {
                        Stop-Function -Message "Issue setting number of log files on $instance" -Target $instance -ErrorRecord $_ -Exception $_.Exception.InnerException.InnerException.InnerException -Continue -FunctionName Set-DbaErrorLogConfig
                    }
                }
                if ($__realCmdlet.ShouldProcess($server, "Output final results of setting number of log files")) {
                    $server.Refresh()
                    $collection.LogCount = $server.NumberOfLogFiles
                }
            }
        }
        $collection
    }
} $SqlInstance $SqlCredential $LogCount $LogSize $__boundLogCount $__boundLogSize $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Enables SQL Server FileStream at the service and instance levels. Port of
/// public/Enable-DbaFilestream.ps1 (W3-010), the sibling of W3-006 Disable-DbaFilestream.
/// Begin-inline process command with TWO pieces of cross-record state. (1) $level starts as the
/// $FileStreamLevel name->int normalization but the source's 3->2 downgrade (level 3 falls
/// back to 2 at the instance layer) MUTATES it, and the function world's begin scope carries
/// the mutated value into later pipeline records - so the hop emits $level through the
/// __dbatoolsEfLevelCarrier sentinel and the next record's hop seeds from it (codex r1/r2).
/// (2) $result: a clustered record that yields zero nodes leaves the source reading the PRIOR
/// record's $result while a fresh hop reads null - carried the same way (codex r3). The other
/// begin constants ($OutputLookup, the -Force ConfirmPreference tweak) are true per-record
/// locals, and there is NO end hop - the begin constants inline into the process script. DEF-001
/// cond1+cond2 (the process foreach EMITS Get-DbaFilestream per instance AND has reachable
/// Stop-Function -Continue at Connect-DbaInstance / Set-DbaSpConfigure), so the hop STREAMS via
/// InvokeScopedStreaming - a buffered hop would lose an earlier instance's emit when a later
/// instance throws under -EnableException. The pre-loop "ShareName requires level >= 2" guard is
/// a terminating Stop-Function BEFORE any emit, so it is DEF-001-neutral. Substitutions only:
/// $PSCmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess (ConfirmImpact MEDIUM mirrored) and
/// explicit -FunctionName Enable-DbaFilestream on every Stop-Function (W1-090); the body is
/// otherwise verbatim. Surface pinned by migration/baselines/Enable-DbaFilestream.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Enable, "DbaFilestream", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class EnableDbaFilestreamCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instance.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Alternative Windows credential for the target server.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 2)]
    public PSCredential? Credential { get; set; }

    /// <summary>The FileStream access level to enable (name or numeric 1/2/3).</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    [ValidateSet("TSql", "TSqlIoStreaming", "TSqlIoStreamingRemoteClient", "1", "2", "3")]
    public string FileStreamLevel { get; set; } = "1";

    /// <summary>The Windows file share name for FileStream data (requires level >= 2).</summary>
    [Parameter(Position = 4)]
    public string? ShareName { get; set; }

    /// <summary>Bypasses confirmation and restarts the SQL Server service to apply changes immediately.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

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
            if (item?.Properties["__dbatoolsEfLevelCarrier"] is not null &&
                LanguagePrimitives.IsTrue(item.Properties["__dbatoolsEfLevelCarrier"].Value))
            {
                // DEF-011/012: the source's begin-initialized $level (with the 3->2 downgrade)
                // persists across pipeline records; the hop emits it via this carrier and the
                // next record's hop seeds from it.
                _carriedLevel = item.Properties["Level"]?.Value;
                _carriedResult = item.Properties["Result"]?.Value;
                _carriedResultAssigned = item.Properties["ResultAssigned"]?.Value;
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Credential, FileStreamLevel, ShareName, Force.ToBool(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"),
            _carriedLevel, _carriedResult, _carriedResultAssigned);
    }

    private object? _carriedLevel;
    private object? _carriedResult;
    private object? _carriedResultAssigned;

    // PS: the begin constants (the $FileStreamLevel name->int normalization, $level,
    // $OutputLookup and the -Force ConfirmPreference tweak) inline ahead of the process body,
    // which is VERBATIM per record. Substitutions only: $PSCmdlet -> $__realCmdlet, explicit
    // -FunctionName Enable-DbaFilestream on Stop-Function (W1-090).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Credential, $FileStreamLevel, $ShareName, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug, $__carriedLevel, $__carriedResult, $__carriedResultAssigned)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [PSCredential]$Credential, [string]$FileStreamLevel, [string]$ShareName, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug, $__carriedLevel, $__carriedResult, $__carriedResultAssigned)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($FileStreamLevel -notin (1, 2, 3)) {
        $FileStreamLevel = switch ($FileStreamLevel) {
            "TSql" {
                1
            }
            "TSqlIoStreaming" {
                2
            }
            "TSqlIoStreamingRemoteClient" {
                3
            }
        }
    }
    # = $finallevel removed as it was identified as a unused variable
    $level = [int]$FileStreamLevel
    # DEF-011/012 (codex): the source initializes $level ONCE in begin and the 3->2 downgrade
    # at :170 persists into later pipeline records; each hop re-inlines begin, so the
    # prior-record value is seeded from the sentinel carrier when present.
    if ($null -ne $__carriedLevel) { $level = [int]$__carriedLevel }
    if ($null -ne $__carriedResultAssigned -and [bool]$__carriedResultAssigned) { $result = $__carriedResult }
    $OutputLookup = @{
        0 = 'Disabled'
        1 = 'FileStream enabled for T-Sql access'
        2 = 'FileStream enabled for T-Sql and IO streaming access'
        3 = 'FileStream enabled for T-Sql, IO streaming, and remote clients'
    }

    if ($Force) { $ConfirmPreference = 'none' }

    if ($ShareName -and $level -lt 2) {
        Stop-Function -Message "Filestream must be at least level 2 when using ShareName" -FunctionName Enable-DbaFilestream
        return
    }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Enable-DbaFilestream
        }

        $filestreamstate = [int]$server.Configuration.FilestreamAccessLevel.ConfigValue

        if ($Force -or $__realCmdlet.ShouldProcess($instance, "Changing from '$($OutputLookup[$filestreamstate])' to '$($OutputLookup[$level])' at the instance level")) {
            # Server level
            if ($server.IsClustered) {
                $nodes = Get-DbaWsfcNode -ComputerName $instance
                foreach ($node in $nodes.Name) {
                    $result = Set-FileSystemSetting -Instance $node -Credential $Credential -ShareName $ShareName -FilestreamLevel $level
                }
            } else {
                $result = Set-FileSystemSetting -Instance $instance -Credential $Credential -ShareName $ShareName -FilestreamLevel $level
            }

            # Instance level
            if ($level -eq 3) {
                $level = 2
            }

            try {
                $null = Set-DbaSpConfigure -SqlInstance $server -Name FilestreamAccessLevel -Value $level -EnableException
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Enable-DbaFilestream
            }

            if ($Force) {
                #$restart replaced with $null as it was identified as a unused variable
                $null = Restart-DbaService -ComputerName $server.ComputerName -InstanceName $server.ServiceName -Type Engine -Force
            }

            Get-DbaFilestream -SqlInstance $instance -SqlCredential $SqlCredential -Credential $Credential
            if ($filestreamstate -ne $level -and -not $Force) {
                Write-Message -Level Warning -Message "[$instance] $result" -FunctionName Enable-DbaFilestream -ModuleName "dbatools"
            }
        }
    }
    [pscustomobject]@{ __dbatoolsEfLevelCarrier = $true; Level = $level; Result = $result; ResultAssigned = [bool](Get-Variable result -Scope 0 -ErrorAction SilentlyContinue) }
} $SqlInstance $SqlCredential $Credential $FileStreamLevel $ShareName $Force $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug $__carriedLevel $__carriedResult $__carriedResultAssigned @__commonParameters 3>&1 2>&1
""";
}

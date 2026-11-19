#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Disables SQL Server FileStream at the service and instance levels. Port of
/// public/Disable-DbaFilestream.ps1 (W3-006). Pure per-record process command: the begin
/// block only sets local constants ($level / $FileStreamLevel / $OutputLookup) consumed
/// inside the same process body, so there is NO cross-record accumulator and NO end hop -
/// the begin constants inline into the process script. DEF-001 cond1+cond2 (the process
/// foreach EMITS Get-DbaFilestream per instance AND has reachable Stop-Function -Continue at
/// Connect-DbaInstance / Set-DbaSpConfigure), so the hop STREAMS via InvokeScopedStreaming -
/// a buffered hop would lose an earlier instance's emit when a later instance throws under
/// -EnableException. Substitutions only: $PSCmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess
/// (ConfirmImpact HIGH mirrored) and explicit -FunctionName Disable-DbaFilestream on every
/// Stop-Function (W1-090); the body is otherwise verbatim. Surface pinned by
/// migration/baselines/Disable-DbaFilestream.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Disable, "DbaFilestream", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class DisableDbaFilestreamCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipelineByPropertyName = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instance.</summary>
    [Parameter(Position = 1, ValueFromPipelineByPropertyName = true)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Alternative Windows credential for the target server.</summary>
    [Parameter(Position = 2, ValueFromPipelineByPropertyName = true)]
    public PSCredential? Credential { get; set; }

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
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Credential, Force.ToBool(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin constants ($level / $FileStreamLevel / $OutputLookup and the -Force
    // ConfirmPreference tweak) inline ahead of the process foreach, which is VERBATIM per
    // record. Substitutions only: $PSCmdlet -> $__realCmdlet, explicit -FunctionName
    // Disable-DbaFilestream on Stop-Function (W1-090).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Credential, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [PSCredential]$Credential, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $FileStreamLevel = $level = 0

    $OutputLookup = @{
        0 = 'Disabled'
        1 = 'FileStream enabled for T-Sql access'
        2 = 'FileStream enabled for T-Sql and IO streaming access'
        3 = 'FileStream enabled for T-Sql, IO streaming, and remote clients'
    }

    if ($Force) { $ConfirmPreference = 'none' }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Disable-DbaFilestream
        }

        # Instance level
        $filestreamstate = [int]$server.Configuration.FilestreamAccessLevel.RunValue

        if ($Force -or $__realCmdlet.ShouldProcess($instance, "Changing from '$($OutputLookup[$filestreamstate])' to '$($OutputLookup[$level])' at the instance level")) {
            try {
                $null = Set-DbaSpConfigure -SqlInstance $server -Name FilestreamAccessLevel -Value $level -EnableException
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Disable-DbaFilestream
            }


            # Server level
            if ($server.IsClustered) {
                $nodes = Get-DbaWsfcNode -ComputerName $instance -Credential $Credential
                foreach ($node in $nodes.Name) {
                    $result = Set-FileSystemSetting -Instance $node -Credential $Credential -FilestreamLevel $FileStreamLevel
                }
            } else {
                $result = Set-FileSystemSetting -Instance $instance -Credential $Credential -FilestreamLevel $FileStreamLevel
            }

            if ($Force) {
                #$restart replaced with $null as it was identified as a unused variable
                $null = Restart-DbaService -ComputerName $instance.ComputerName -InstanceName $server.ServiceName -Type Engine -Force
            }

            Get-DbaFilestream -SqlInstance $instance -SqlCredential $SqlCredential -Credential $Credential

            if ($filestreamstate -ne $level -and -not $Force) {
                Write-Message -Level Warning -Message "[$instance] $result" -FunctionName Disable-DbaFilestream -ModuleName "dbatools"
            }
        }
    }
} $SqlInstance $SqlCredential $Credential $Force $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets the TCP port(s) for instances (delegating to Set-DbaNetworkConfiguration).
/// Port of public/Set-DbaTcpPort.ps1 (W3-098). WHOLE-RECORD verbatim hop. VFP-LOCAL
/// CLASSIFICATION TABLE (SqlInstance is the sole VFP; promoted question answered): the
/// only param mutation is `$IpAddress = $null` under the literal 0.0.0.0 coercion -
/// source keeps it in the fn scope across records, the port re-runs the coercion per
/// hop, and the results are IDENTICAL because the mutation is IDEMPOTENT (0.0.0.0
/// always coerces to null; a real address never mutates) - no sentinel;
/// $computerFullName/$instanceName/$netConf/$ipConf are per-iteration. SOURCE QUIRK
/// preserved: the IpAddress-with-multiple-servers guard tests $SqlInstance.Count per
/// RECORD, so PIPED instances slip past it one at a time (only the array form blocks).
/// Gates route to the REAL cmdlet ($Pscmdlet/$PSCmdlet -> $__realCmdlet; -Force here
/// means RESTART, not confirm-suppression - no ConfirmPreference convention, no
/// transplant, hold-free). The single Test-Bound call rides as a carried flag (W3-093
/// law). Nested delegates ride verbatim: Set-DbaNetworkConfiguration (named AND piped
/// call shapes), Get-DbaNetworkConfiguration -OutputType Full, Restart-DbaService
/// -Force -EnableException. [PsIntArrayCast] on the Mandatory ValidateRange Port
/// (the W1-043 class over arrays, introduced this row: a null ELEMENT becomes 0 before
/// validation so the rejection carries the RANGE message exactly like the script
/// binder; conservative per the W3-076 lesson). All mutating paths are env-blocked on
/// the lane topology (WMI via the delegates); the smoke exercises the deep paths via
/// module-scope SHADOWS of the three delegates with captured-argument pins (the
/// W3-084/W3-097 technique). NO WarningAction carrier (codex W3-005 r3). Surface
/// pinned by migration/baselines/Set-DbaTcpPort.json (implicit positions 0-3,
/// SqlInstance Mandatory pos0 VFP, Port int[] Mandatory pos2 ValidateRange 1-65535,
/// IpAddress System.Net.IPAddress[] pos3, ConfirmImpact High).
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaTcpPort", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class SetDbaTcpPortCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Windows credential for the remote network configuration work.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>The port(s) to configure (1-65535).</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [PsIntArrayCast]
    [ValidateRange(1, 65535)]
    public int[] Port { get; set; } = null!;

    /// <summary>Specific IP address(es) to configure instead of IPAll.</summary>
    [Parameter(Position = 3)]
    public System.Net.IPAddress[]? IpAddress { get; set; }

    /// <summary>Restarts the Engine service after the change.</summary>
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
            SqlInstance, Credential, Port, IpAddress, Force.ToBool(),
            EnableException.ToBool(), TestBound(nameof(Force)), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the ENTIRE process body VERBATIM per record. Substitutions only:
    // $Pscmdlet/$PSCmdlet -> $__realCmdlet on the three gates, Test-Bound -ParameterName
    // Force -> the carried flag, and explicit -FunctionName Set-DbaTcpPort on
    // Stop-Function/Write-Message (W1-090). The verbatim Test-FunctionInterrupt gate,
    // the 0.0.0.0 coercion, the per-record collection guard and the nested delegate
    // calls (incl. the piped $netConf | Set-DbaNetworkConfiguration shape) ride as-is.
    private const string ProcessScript = """
param($SqlInstance, $Credential, $Port, $IpAddress, $Force, $EnableException, $__boundForce, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$Credential, [int[]]$Port, [System.Net.IPAddress[]]$IpAddress, $Force, $EnableException, $__boundForce, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if (Test-FunctionInterrupt) {
            return
        }

        if ('0.0.0.0' -eq $IpAddress) {
            $IpAddress = $null
        }

        if ($IpAddress -and $SqlInstance.Count -gt 1) {
            Stop-Function -Message "-IpAddress switch cannot be used with a collection of serveraddresses" -Target $SqlInstance -FunctionName Set-DbaTcpPort
            return
        }

        foreach ($instance in $SqlInstance) {
            $computerFullName = $instance.ComputerName
            $instanceName = $instance.InstanceName
            if (-not $IpAddress) {
                if ($__realCmdlet.ShouldProcess($instance, "Setting port to $($Port -join ',') for IPAll of $instance")) {
                    Set-DbaNetworkConfiguration -SqlInstance $instance -Credential $Credential -StaticPortForIPAll $Port -EnableException:$EnableException -Confirm:$false
                }
            } else {
                try {
                    $netConf = Get-DbaNetworkConfiguration -SqlInstance $instance -Credential $Credential -OutputType Full -EnableException
                } catch {
                    Stop-Function -Message "Failed to collect network configuration from $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue -FunctionName Set-DbaTcpPort
                }

                $netConf.TcpIpEnabled = $true
                $netConf.TcpIpProperties.Enabled = $true
                $netConf.TcpIpProperties.ListenAll = $false
                foreach ($ip in $IpAddress) {
                    $ipConf = $netConf.TcpIpAddresses | Where-Object { $_.IpAddress -eq $ip }
                    if ($ipConf) {
                        $ipConf.Enabled = $true
                        $ipConf.TcpDynamicPorts = ''
                        $ipConf.TcpPort = $Port -join ','
                    } else {
                        Write-Message -Level Warning -Message "IP address $ip not found, skipping." -FunctionName Set-DbaTcpPort -ModuleName "dbatools"
                    }
                }

                if ($__realCmdlet.ShouldProcess($instance, "Setting port to $($Port -join ',') for IP address $IpAddress of $instance")) {
                    $netConf | Set-DbaNetworkConfiguration -Credential $Credential -EnableException:$EnableException -Confirm:$false
                }

                if ($__boundForce) {
                    if ($__realCmdlet.ShouldProcess($instance, "Force provided, restarting Engine and Agent service for $instance on $computerFullName")) {
                        try {
                            $null = Restart-DbaService -SqlInstance $instance -Type Engine -Force -EnableException
                        } catch {
                            Stop-Function -Message "Issue restarting $instance on $computerFullName" -Target $instance -Continue -ErrorRecord $_ -FunctionName Set-DbaTcpPort
                        }
                    }
                }
            }
        }
    }
} $SqlInstance $Credential $Port $IpAddress $Force $EnableException $__boundForce $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

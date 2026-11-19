#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Gets the TCP port(s) SQL Server instances listen on. Port of public/Get-DbaTcpPort.ps1 (W3-054).
/// Pure per-record process command with no begin/end blocks. DEF-001 cond1+cond2: the process foreach
/// EMITS per IP (the -All path) and/or per instance (the default T-SQL path) AND has reachable
/// Stop-Function -Continue at Get-DbaNetworkConfiguration / Connect-DbaInstance, so the hop STREAMS via
/// InvokeScopedStreaming. Cross-record-state check: $someIps is reassigned at the top of each -All
/// iteration (or, when -not $All, is never read because the "-not $All" short-circuits before it), so
/// there is no stale carry. No ShouldProcess, no cross-record state, no carriers beyond the parameters.
/// Positions match the retired function (SqlInstance=0, SqlCredential=1, Credential=2; All/ExcludeIpv6/
/// EnableException=switch/null) and the ExcludeIpv6 alias (Ipv4) is preserved. Substitution only:
/// explicit -FunctionName Get-DbaTcpPort on Stop-Function (W1-090); the body is otherwise verbatim.
/// Surface pinned by migration/baselines/Get-DbaTcpPort.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaTcpPort")]
public sealed class GetDbaTcpPortCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Alternative Windows credential for the -All network configuration query.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    /// <summary>Returns all IP/port configuration details, not just the effective port.</summary>
    [Parameter]
    public SwitchParameter All { get; set; }

    /// <summary>With -All, returns only IPv4 addresses.</summary>
    [Parameter]
    [Alias("Ipv4")]
    public SwitchParameter ExcludeIpv6 { get; set; }

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
            SqlInstance, SqlCredential, Credential, All.ToBool(), ExcludeIpv6.ToBool(), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM per record (no begin/end blocks). Substitution only: explicit
    // -FunctionName Get-DbaTcpPort on Stop-Function (W1-090).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Credential, $All, $ExcludeIpv6, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [PSCredential]$Credential, $All, $ExcludeIpv6, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($instance in $SqlInstance) {
        if ($All) {
            try {
                $netConf = Get-DbaNetworkConfiguration -SqlInstance $instance -Credential $Credential -OutputType Full -EnableException
            } catch {
                Stop-Function -Message "Failed to collect network configuration from $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue -FunctionName Get-DbaTcpPort
            }

            $someIps = foreach ($ip in $netConf.TcpIpAddresses) {
                # A setting is only used if either ListenAll is active and it is IPAll or if ListenAll is not active and the IPn is enabled.
                $isIPAll = $netConf.TcpIpProperties.ListenAll -and $ip.Name -eq 'IPAll'
                $isIPnEnabled = -not $netConf.TcpIpProperties.ListenAll -and $ip.Enabled
                $isUsed = $isIPAll -or $isIPnEnabled
                [PSCustomObject]@{
                    ComputerName    = $netConf.ComputerName
                    InstanceName    = $netConf.InstanceName
                    SqlInstance     = $netConf.SqlInstance
                    Name            = $ip.Name
                    Active          = $ip.Active
                    Enabled         = $ip.Enabled
                    IpAddress       = $ip.IpAddress
                    TcpDynamicPorts = $ip.TcpDynamicPorts
                    TcpPort         = $ip.TcpPort
                    IsUsed          = $isUsed
                }
            }

            $results = $someIps | Sort-Object IPAddress

            if ($ExcludeIpv6) {
                $octet = '(?:0?0?[0-9]|0?[1-9][0-9]|1[0-9]{2}|2[0-5][0-5]|2[0-4][0-9])'
                [regex]$ipv4 = "^(?:$octet\.){3}$octet$"
                $results = $results | Where-Object { $_.IPAddress -match $ipv4 }
            }

            $results
        }
        #Default Execution of Get-DbaTcpPort
        if (-not $All -or ($All -and ($null -eq $someIps))) {
            try {
                # Using "-NetworkProtocol TcpIp" does not work if $instance is a Server SMO - so we have to use a string to force a new connection:
                $server = Connect-DbaInstance -SqlInstance "TCP:$instance" -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Get-DbaTcpPort
            }

            # WmiComputer can be unreliable :( Use T-SQL
            $sql = "SELECT local_net_address, local_tcp_port FROM sys.dm_exec_connections WHERE session_id = @@SPID"
            $port = $server.Query($sql)

            [PSCustomObject]@{
                ComputerName = $server.ComputerName
                InstanceName = $server.ServiceName
                SqlInstance  = $server.DomainInstanceName
                IPAddress    = $port.local_net_address
                Port         = $port.local_tcp_port
                Static       = $true
                Type         = "Normal"
            } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, IPAddress, Port
        }
    }
} $SqlInstance $SqlCredential $Credential $All $ExcludeIpv6 $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

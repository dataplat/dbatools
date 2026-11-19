#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Gets SQL Server network protocols for computers. Port of
/// public/Get-DbaInstanceProtocol.ps1 (W3-038). Pure per-record process command with no begin/end
/// blocks. DEF-001 cond1+cond2: the process body EMITS a decorated protocol per item
/// (Select-DefaultView) AND has reachable Stop-Function -Continue at the namespace / protocol WMI
/// queries, so the hop STREAMS via InvokeScopedStreaming. Every per-computer variable ($Server,
/// $namespaces, $instance, $prot) is set at the top of its code path or the iteration continues
/// before it is read, so there is no cross-record carry. No ShouldProcess, no cross-record state. The
/// ComputerName default ($env:COMPUTERNAME) is applied in ProcessRecord ONLY when the parameter was
/// not explicitly bound. Positions match the retired function (ComputerName=0, Credential=1;
/// EnableException=switch/null) and the ComputerName aliases (cn / host / Server) are preserved.
/// Substitution only: explicit -FunctionName Get-DbaInstanceProtocol on Stop-Function (W1-090); the
/// body is otherwise verbatim. Surface pinned by migration/baselines/Get-DbaInstanceProtocol.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaInstanceProtocol")]
public sealed class GetDbaInstanceProtocolCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s). Defaults to the local computer.</summary>
    [Parameter(Position = 0, ValueFromPipeline = true)]
    [Alias("cn", "host", "Server")]
    public DbaInstanceParameter[]? ComputerName { get; set; }

    /// <summary>Alternative Windows credential for the WMI queries.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // PS: [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME - apply the default ONLY when
        // the parameter was not explicitly bound (an explicit $null/@() must NOT fall back to localhost).
        DbaInstanceParameter[]? computers = ComputerName;
        if (!MyInvocation.BoundParameters.ContainsKey("ComputerName") && (computers is null || computers.Length == 0))
        {
            string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
            if (!string.IsNullOrEmpty(machine))
                computers = new[] { new DbaInstanceParameter(machine) };
        }

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
            computers, Credential, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM per record (no begin/end blocks). Substitution only: explicit
    // -FunctionName Get-DbaInstanceProtocol on Stop-Function (W1-090). ComputerName arrives already
    // defaulted to the computer name by ProcessRecord.
    private const string ProcessScript = """
param($ComputerName, $Credential, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$ComputerName, [PSCredential]$Credential, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($Computer in $ComputerName.ComputerName) {
        $Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $Credential
        if ($Server.FullComputerName) {
            $Computer = $server.FullComputerName
            Write-Message -Level Verbose -Message "Getting SQL Server namespace on $computer" -FunctionName Get-DbaInstanceProtocol -ModuleName "dbatools"

            $cmNamespace = 'root\Microsoft\SQLServer'
            try {
                $cmGetInstanceParams = @{
                    ComputerName = $Computer
                    Credential   = $Credential
                    Namespace    = $cmNamespace
                    Query        = "SELECT * FROM __NAMESPACE WHERE Name Like 'ComputerManagement%'"
                    ErrorAction  = 'Stop'
                }
                $namespaces = Get-DbaCmObject @cmGetInstanceParams
                Write-Message -Level Verbose -Message "Successfully retrieved namespaces from $Computer. Total found: $($namespaces.Count)" -FunctionName Get-DbaInstanceProtocol -ModuleName "dbatools"
            } catch {
                Stop-Function -Message "Failed to retrieve ComputerManagement namespace" -Category ConnectionError -ErrorRecord $_ -Target $Computer -Continue -FunctionName Get-DbaInstanceProtocol
            }
            if ($namespaces) {
                try {
                    $instance = $namespaces | Where-Object { (Get-DbaCmObject -ComputerName $Computer -Credential $Credential -Namespace "$cmNamespace\$($_.Name)" -ClassName ServerNetworkProtocol -ErrorAction Stop).count -gt 0 } | Sort-Object Name -Descending | Select-Object -First 1
                    Write-Message -Level Verbose -Message "Successfully retrieved ServerNetworkProtocol data from $Computer" -FunctionName Get-DbaInstanceProtocol -ModuleName "dbatools"
                } catch {
                    Stop-Function -Message "Failed to retrieve Network Protcol data" -ErrorRecord $_ -Target $Computer -Continue -FunctionName Get-DbaInstanceProtocol
                }
            } else {
                Stop-Function -Message "No ComputerManagement namespaces found" -Target $Computer -Continue -FunctionName Get-DbaInstanceProtocol
            }
            if ($instance.Name) {
                $instanceName = $instance.Name
                Write-Message -Level Verbose -Message "Getting Cim class ServerNetworkProtocol in Namespace $instanceName on $Computer" -FunctionName Get-DbaInstanceProtocol -ModuleName "dbatools"
                try {
                    $prot = Get-DbaCmObject -ComputerName $Computer -Credential $Credential -Namespace "$cmNamespace\$($instanceName)" -ClassName ServerNetworkProtocol -ErrorAction Stop

                    $prot | Add-Member -Force -MemberType ScriptMethod -Name Enable -Value { Invoke-CimMethod -MethodName SetEnable -InputObject $this }
                    $prot | Add-Member -Force -MemberType ScriptMethod -Name Disable -Value { Invoke-CimMethod -MethodName SetDisable -InputObject $this }
                    foreach ($protocol in $prot) { Select-DefaultView -InputObject $protocol -Property 'PSComputerName as ComputerName', 'InstanceName', 'ProtocolDisplayName as DisplayName', 'ProtocolName as Name', 'MultiIpConfigurationSupport as MultiIP', 'Enabled as IsEnabled' }
                } catch {
                    Write-Message -Level Warning -Message "Issue gathering ServerNetworkProtocol data on $Computer" -FunctionName Get-DbaInstanceProtocol -ModuleName "dbatools"
                }
            } else {
                Write-Message -Level Warning -Message "No ComputerManagement Namespace on $Computer. Please note that this function is available from SQL 2005 up." -FunctionName Get-DbaInstanceProtocol -ModuleName "dbatools"
            }
        } else {
            Write-Message -Level Warning -Message "Failed to connect to $Computer" -FunctionName Get-DbaInstanceProtocol -ModuleName "dbatools"
        }
    }
} $ComputerName $Credential $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

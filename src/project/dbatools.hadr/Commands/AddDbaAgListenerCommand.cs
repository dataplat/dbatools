#nullable enable

using System.Collections;
using System.Management.Automation;
using System.Net;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Adds a listener to one or more availability groups, building the listener and its IP
/// address entries from explicit addresses, calculated or explicit subnets, or DHCP.
/// Port of public/Add-DbaAgListener.ps1; surface pinned by
/// migration/baselines/Add-DbaAgListener.json.
/// </summary>
[Cmdlet(VerbsCommon.Add, "DbaAgListener", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class AddDbaAgListenerCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instances hosting the availability groups.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The availability groups to add the listener to.</summary>
    [Parameter(Position = 2)]
    public string[]? AvailabilityGroup { get; set; }

    /// <summary>The listener name; defaults to the availability group name.</summary>
    [Parameter(Position = 3)]
    public string? Name { get; set; }

    /// <summary>Static IP address or addresses for the listener.</summary>
    [Parameter(Position = 4)]
    public IPAddress[]? IPAddress { get; set; }

    /// <summary>Subnet IP or IPs; calculated from address and mask when omitted.</summary>
    [Parameter(Position = 5)]
    public IPAddress[]? SubnetIP { get; set; }

    /// <summary>Subnet mask or masks for the listener addresses.</summary>
    [Parameter(Position = 6)]
    public IPAddress[]? SubnetMask { get; set; } =
        (IPAddress[])LanguagePrimitives.ConvertTo("255.255.255.0", typeof(IPAddress[]), System.Globalization.CultureInfo.InvariantCulture);

    /// <summary>The port the listener listens on.</summary>
    [Parameter(Position = 7)]
    public int Port { get; set; } = 1433;

    /// <summary>Uses DHCP for the listener address.</summary>
    [Parameter]
    public SwitchParameter Dhcp { get; set; }

    /// <summary>Returns the uncreated listener object for further customization.</summary>
    [Parameter]
    public SwitchParameter Passthru { get; set; }

    /// <summary>Availability group objects piped in, for example from Get-DbaAvailabilityGroup.</summary>
    [Parameter(Position = 8, ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4002State"))
            {
                _state = sentinel["__w4002State"] as Hashtable;
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
            SqlInstance, SqlCredential, AvailabilityGroup, Name, IPAddress, SubnetIP,
            SubnetMask, Port, Dhcp.ToBool(), Passthru.ToBool(), InputObject,
            EnableException.ToBool(), _state, this,
            BoundFlag("SqlInstance"), BoundFlag("InputObject"), BoundFlag("AvailabilityGroup"),
            BoundFlag("IPAddress"), BoundFlag("SubnetIP"), BoundFlag("Name"),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private bool BoundFlag(string name)
    {
        return MyInvocation.BoundParameters.ContainsKey(name);
    }

    // PS: the process block VERBATIM inside a dot-sourced block, so the six latching
    // Stop-Function+return sites (write-only latches: the source has no
    // Test-FunctionInterrupt, each record re-validates fully) and the Passthru return
    // exit the dot-block while the state tail still runs. The source MUTATES the
    // SubnetMask/SubnetIP parameters (single-mask/single-subnet expansion) and function
    // scope persists those across records, so records after the first restore the
    // carried values before the read sites. Substitutions: seven Test-Bound calls become
    // carried bound-flags (Test-Bound scope-walks the caller and can never ride a hop;
    // originals kept as SOURCE comments per site), one ShouldProcess routes to the real
    // cmdlet, seven -FunctionName appends.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AvailabilityGroup, $Name, $IPAddress, $SubnetIP, $SubnetMask, $Port, $Dhcp, $Passthru, $InputObject, $EnableException, $__state, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundAvailabilityGroup, $__boundIPAddress, $__boundSubnetIP, $__boundName, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$AvailabilityGroup, [string]$Name, [ipaddress[]]$IPAddress, [ipaddress[]]$SubnetIP, [ipaddress[]]$SubnetMask, [int]$Port, $Dhcp, $Passthru, [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject, $EnableException, $__state, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundAvailabilityGroup, $__boundIPAddress, $__boundSubnetIP, $__boundName, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($null -ne $__state) {
        $SubnetMask = $__state.subnetMask
        $SubnetIP = $__state.subnetIP
    }
    . {
        if (-not ($__boundSqlInstance -or $__boundInputObject)) { # SOURCE: if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Add-DbaAgListener
            return
        }

        if (($__boundSqlInstance) -and (-not $__boundAvailabilityGroup)) { # SOURCE: if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName AvailabilityGroup)) {
            Stop-Function -Message "You must specify one or more databases and one or more Availability Groups when using the SqlInstance parameter." -FunctionName Add-DbaAgListener
            return
        }

        if ($Dhcp) {
            if ($__boundIPAddress) { # SOURCE: if (Test-Bound -ParameterName IPAddress) {
                Stop-Function -Message "You cannot specify both an IP address and the Dhcp switch." -FunctionName Add-DbaAgListener
                return
            }

            if ($SubnetMask.Count -gt 1 -or $SubnetIP.Count -gt 1) {
                Stop-Function -Message "You can only specify a single subnet when using Dhcp." -FunctionName Add-DbaAgListener
                return
            }
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }

        if ($__boundIPAddress) { # SOURCE: if (Test-Bound -ParameterName IPAddress) {
            if ($IPAddress.Count -ne $SubnetMask.Count) {
                if ($SubnetMask.Count -eq 1) {
                    # If one subnet mask is supplied, let's assume we want to use the same one for every IP
                    $SubnetMask = $SubnetMask * $IPAddress.Count
                } else {
                    Stop-Function -Message "When specifying multiple IP addresses, the number of subnet masks must match, or give one mask to be used for all IP addresses." -FunctionName Add-DbaAgListener
                    return
                }
            }

            if (-not $__boundSubnetIP) { # SOURCE: if (Test-Bound -Not -ParameterName SubnetIP) {
                # No subnets (subnet IPs) were supplied but we can calculate them with the netmask
                $SubnetIP = for ($ipIndex = 0 ; $ipIndex -lt $IPAddress.Count ; $ipIndex++) {
                    ($IPAddress[$ipIndex].Address -band $SubnetMask[$ipIndex].Address) -as [ipaddress]
                }
            } else {
                if ($IPAddress.Count -ne $SubnetIP.Count) {
                    if ($SubnetIP.Count -eq 1) {
                        # If one subnet IP is supplied, let's assume we want to use the same subnet for every IP
                        $SubnetIP = $SubnetIP * $IPAddress.Count
                    } else {
                        Stop-Function -Message "When specifying subnet IPs explicitly, the number of subnets must match the number of IPs, or use one subnet to be applied to all IPs." -FunctionName Add-DbaAgListener
                        return
                    }
                }
            }
        }

        foreach ($ag in $InputObject) {
            if ((-not $__boundName)) { # SOURCE: if ((Test-Bound -Not -ParameterName Name)) {
                $Name = $ag.Name
            }
            if ($__realCmdlet.ShouldProcess($ag.Parent.Name, "Adding $($IPAddress.IPAddressToString) to $($ag.Name)")) {
                try {
                    $aglistener = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener -ArgumentList $ag, $Name
                    $aglistener.PortNumber = $Port

                    $ipIndex = 0
                    do {
                        # add the IPs
                        $listenerip = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroupListenerIPAddress -ArgumentList $aglistener

                        if ($__boundIPAddress) { # SOURCE: if (Test-Bound -ParameterName IPAddress) {
                            $listenerip.IPAddress = $IPAddress[$ipIndex]
                        }

                        if ($SubnetIP) {
                            $listenerip.SubnetMask = $SubnetMask[$ipIndex]
                            $listenerip.SubnetIP = $SubnetIP[$ipIndex]
                        }

                        $listenerip.IsDHCP = $Dhcp
                        $aglistener.AvailabilityGroupListenerIPAddresses.Add($listenerip)
                    } while ((++$ipIndex) -lt $IPAddress.Count)

                    if ($Passthru) {
                        return $aglistener
                    } else {
                        # something is up with .net create(), force a stop
                        Invoke-Create -Object $aglistener
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -FunctionName Add-DbaAgListener
                }
                Get-DbaAgListener -SqlInstance $ag.Parent -AvailabilityGroup $ag.Name -Listener $Name
            }
        }
    }
    @{ __w4002State = @{
        subnetMask = $SubnetMask
        subnetIP   = $SubnetIP
    } }
} $SqlInstance $SqlCredential $AvailabilityGroup $Name $IPAddress $SubnetIP $SubnetMask $Port $Dhcp $Passthru $InputObject $EnableException $__state $__realCmdlet $__boundSqlInstance $__boundInputObject $__boundAvailabilityGroup $__boundIPAddress $__boundSubnetIP $__boundName $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

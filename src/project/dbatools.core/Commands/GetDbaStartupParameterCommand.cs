#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Server startup parameters from the Windows service configuration.
/// Port of public/Get-DbaStartupParameter.ps1; surface pinned by migration/baselines/Get-DbaStartupParameter.json.
/// The WMI work rides the source's own Invoke-ManagedComputerCommand call so the
/// local-DCOM-then-WinRM fallback ladder applies: a direct ManagedComputer connection
/// throws "RPC server is unavailable" on hosts that only allow remoting, where the
/// shipped function silently degrades to remote execution.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaStartupParameter")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaStartupParameterCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Allows you to login to servers using alternate Windows credentials.</summary>
    [Parameter(Position = 1)]
    [Alias("SqlCredential")]
    public PSCredential? Credential { get; set; }

    /// <summary>Returns only essential startup information: file paths, trace flags, and the parameter string.</summary>
    [Parameter]
    public SwitchParameter Simple { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
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
            new DbaInstanceParameter[] { instance }, Credential,
                Simple.ToBool(), EnableException.ToBool(),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
        }
    }

    // PS: the source process foreach VERBATIM, one element per hop invocation (the
    // source loop line doubles as the guard loop, so the catch's -Continue lands on it
    // exactly like the function world). Substitution only: -FunctionName appended to
    // the catch-path Stop-Function (the hop scriptblock has no function frame to stamp).
    private const string ProcessScript = """
param($SqlInstance, $Credential, $Simple, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$Credential, $Simple, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($instance in $SqlInstance) {
        try {
                $computerName = $instance.ComputerName
                $instanceName = $instance.InstanceName
                $ogInstance = $instance.FullSmoName

                $scriptBlock = {
                    $computerName = $args[0]
                    $instanceName = $args[1]
                    $ogInstance = $args[2]
                    $Simple = $args[3]

                    $serviceDisplayName = "SQL Server ($instanceName)"
                    $wmisvc = @($wmi.Services | Where-Object DisplayName -eq $serviceDisplayName)

                    if ($wmisvc.Count -eq 0) {
                        throw "SQL Server service '$serviceDisplayName' was not found on $computerName."
                    }

                    if ($wmisvc.Count -gt 1) {
                        throw "Multiple SQL Server services named '$serviceDisplayName' were found on $computerName."
                    }

                    $wmisvc = $wmisvc[0]

                    $params = $wmisvc.StartupParameters -split ';'

                    $masterData = $params | Where-Object { $_.StartsWith('-d') }
                    $masterLog = $params | Where-Object { $_.StartsWith('-l') }
                    $errorLog = $params | Where-Object { $_.StartsWith('-e') }
                    $traceFlags = $params | Where-Object { $_.StartsWith('-T') }
                    $debugFlags = $params | Where-Object { $_.StartsWith('-t') }

                    if ($traceFlags.length -eq 0) {
                        $traceFlags = "None"
                    } else {
                        $traceFlags = [int[]]$traceFlags.substring(2)
                    }

                    if ($debugFlags.length -eq 0) {
                        $debugFlags = "None"
                    } else {
                        $debugFlags = [int[]]$debugFlags.substring(2)
                    }

                    if ($Simple -eq $true) {
                        [PSCustomObject]@{
                            ComputerName    = $computerName
                            InstanceName    = $instanceName
                            SqlInstance     = $ogInstance
                            MasterData      = $masterData.TrimStart('-d')
                            MasterLog       = $masterLog.TrimStart('-l')
                            ErrorLog        = $errorLog.TrimStart('-e')
                            TraceFlags      = $traceFlags
                            DebugFlags      = $debugFlags
                            ParameterString = $wmisvc.StartupParameters
                        }
                    } else {
                        # From https://msdn.microsoft.com/en-us/library/ms190737.aspx

                        $commandPromptParm = $params | Where-Object { $_ -eq '-c' }
                        $minimalStartParm = $params | Where-Object { $_ -eq '-f' }
                        $memoryToReserve = $params | Where-Object { $_.StartsWith('-g') }
                        $noEventLogsParm = $params | Where-Object { $_ -eq '-n' }
                        $instanceStartParm = $params | Where-Object { $_ -eq '-s' }
                        $disableMonitoringParm = $params | Where-Object { $_ -eq '-x' }
                        $increasedExtentsParm = $params | Where-Object { $_ -ceq '-E' }

                        $minimalStart = $noEventLogs = $instanceStart = $disableMonitoring = $false
                        $increasedExtents = $commandPrompt = $singleUser = $false

                        if ($null -ne $commandPromptParm) {
                            $commandPrompt = $true
                        }
                        if ($null -ne $minimalStartParm) {
                            $minimalStart = $true
                        }
                        if ($null -eq $memoryToReserve) {
                            $memoryToReserve = 0
                        }
                        if ($null -ne $noEventLogsParm) {
                            $noEventLogs = $true
                        }
                        if ($null -ne $instanceStartParm) {
                            $instanceStart = $true
                        }
                        if ($null -ne $disableMonitoringParm) {
                            $disableMonitoring = $true
                        }
                        if ($null -ne $increasedExtentsParm) {
                            $increasedExtents = $true
                        }

                        $singleUserParm = $params | Where-Object { $_.StartsWith('-m') }

                        if ($singleUserParm.length -ne 0) {
                            $singleUser = $true
                            $singleUserDetails = $singleUserParm.TrimStart('-m')
                        }

                        [PSCustomObject]@{
                            ComputerName         = $computerName
                            InstanceName         = $instanceName
                            SqlInstance          = $ogInstance
                            MasterData           = $masterData -replace '^-[dD]', ''
                            MasterLog            = $masterLog -replace '^-[lL]', ''
                            ErrorLog             = $errorLog -replace '^-[eE]', ''
                            TraceFlags           = $traceFlags
                            DebugFlags           = $debugFlags
                            CommandPromptStart   = $commandPrompt
                            MinimalStart         = $minimalStart
                            MemoryToReserve      = $memoryToReserve
                            SingleUser           = $singleUser
                            SingleUserName       = $singleUserDetails
                            NoLoggingToWinEvents = $noEventLogs
                            StartAsNamedInstance = $instanceStart
                            DisableMonitoring    = $disableMonitoring
                            IncreasedExtents     = $increasedExtents
                            ParameterString      = $wmisvc.StartupParameters
                        }
                    }
                }

                # This command is in the internal function
                # It's sorta like Invoke-Command.
                if ($Credential) {
                    Invoke-ManagedComputerCommand -Server $computerName -Credential $Credential -ScriptBlock $scriptBlock -ArgumentList $computerName, $instanceName, $ogInstance, $Simple
                } else {
                    Invoke-ManagedComputerCommand -Server $computerName -ScriptBlock $scriptBlock -ArgumentList $computerName, $instanceName, $ogInstance, $Simple
                }
        } catch {
            Stop-Function -Message "$instance failed." -ErrorRecord $_ -Continue -Target $instance -FunctionName Get-DbaStartupParameter
        }
    }
} $SqlInstance $Credential $Simple $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

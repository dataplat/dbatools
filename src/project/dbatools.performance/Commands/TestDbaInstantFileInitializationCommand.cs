#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Audits Instant File Initialization privileges for SQL Server Engine services. Port of
/// public/Test-DbaInstantFileInitialization.ps1 (W1-130). The per-record body rides an
/// advanced module-scoped PowerShell hop so service/privilege discovery, private helpers,
/// test mocks, ETS filtering, Boolean truth-table behavior, dynamic continues, streams,
/// and Select-DefaultView retain the function's engine semantics. The unbound ComputerName
/// default is read from the invocation-time COMPUTERNAME environment variable. Surface
/// pinned by migration/baselines/Test-DbaInstantFileInitialization.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaInstantFileInitialization")]
public sealed class TestDbaInstantFileInitializationCommand : DbaBaseCmdlet
{
    /// <summary>SQL Server host computers to audit.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; }

    /// <summary>Alternative Windows credential.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        DbaInstanceParameter[]? computers = ComputerName;
        if (!MyInvocation.BoundParameters.ContainsKey("ComputerName"))
        {
            string? defaultComputer = Environment.GetEnvironmentVariable("COMPUTERNAME");
            computers = defaultComputer is null
                ? null
                : new[] { new DbaInstanceParameter(defaultComputer) };
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            computers, Credential, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string ProcessScript = """
param($ComputerName, $Credential, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($ComputerName, $Credential, $EnableException)

        foreach ($computer in $ComputerName) {
            try {
                Write-Message -Level Verbose -Message "Getting SQL Server Engine services on $computer" -FunctionName Test-DbaInstantFileInitialization -ModuleName "dbatools"
                $splatGetService = @{
                    ComputerName    = $computer
                    Credential      = $Credential
                    Type            = "Engine"
                    EnableException = $EnableException
                }
                $services = Get-DbaService @splatGetService
            } catch {
                Stop-Function -Message "Failed to get SQL Server services on $computer" -ErrorRecord $_ -Target $computer -Continue -FunctionName Test-DbaInstantFileInitialization
            }

            if (-not $services) {
                Write-Message -Level Verbose -Message "No SQL Server Engine services found on $computer" -FunctionName Test-DbaInstantFileInitialization -ModuleName "dbatools"
                continue
            }

            try {
                Write-Message -Level Verbose -Message "Getting Windows privileges on $computer" -FunctionName Test-DbaInstantFileInitialization -ModuleName "dbatools"
                $splatGetPrivilege = @{
                    ComputerName    = $computer
                    Credential      = $Credential
                    EnableException = $EnableException
                }
                $privileges = Get-DbaPrivilege @splatGetPrivilege
            } catch {
                Stop-Function -Message "Failed to get privileges on $computer" -ErrorRecord $_ -Target $computer -Continue -FunctionName Test-DbaInstantFileInitialization
            }

            foreach ($service in $services) {
                Write-Message -Level Verbose -Message "Checking IFI for service $($service.ServiceName) on $computer" -FunctionName Test-DbaInstantFileInitialization -ModuleName "dbatools"

                $serviceVirtualAccount = "NT SERVICE\$($service.ServiceName)"
                $serviceNameIFI = ($privileges | Where-Object User -eq $serviceVirtualAccount).InstantFileInitialization -eq $true
                $startNameIFI = ($privileges | Where-Object User -eq $service.StartName).InstantFileInitialization -eq $true
                $startNameUsesVirtualAccount = $service.StartName -eq $serviceVirtualAccount

                $isEnabled = $serviceNameIFI -or $startNameIFI
                $isBestPractice = $serviceNameIFI -and ($startNameUsesVirtualAccount -or -not $startNameIFI)

                [PSCustomObject]@{
                    ComputerName   = $service.ComputerName
                    InstanceName   = $service.InstanceName
                    ServiceName    = $service.ServiceName
                    StartName      = $service.StartName
                    ServiceNameIFI = $serviceNameIFI
                    StartNameIFI   = $startNameIFI
                    IsEnabled      = $isEnabled
                    IsBestPractice = $isBestPractice
                } | Select-DefaultView -Property ComputerName, InstanceName, ServiceName, StartName, IsEnabled, IsBestPractice
            }
        }

} $ComputerName $Credential $EnableException @__commonParameters 3>&1 2>&1
""";
}


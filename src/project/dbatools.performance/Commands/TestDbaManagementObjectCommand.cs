#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests whether requested SMO major versions exist in a computer's GAC. Port of
/// public/Test-DbaManagementObject.ps1 (W1-131). A single remote ScriptBlock is created
/// for the cmdlet instance, matching the source begin/process lifetime. The process loop
/// rides an advanced module-scoped hop so DbaInstance property projection, Invoke-Command2,
/// ArgumentList expansion, dynamic Stop-Function continues, streams, and module mocks keep
/// PowerShell engine semantics. Surface pinned by
/// migration/baselines/Test-DbaManagementObject.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaManagementObject")]
public sealed class TestDbaManagementObjectCommand : DbaBaseCmdlet
{
    /// <summary>Computers whose GAC should be inspected.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; }

    /// <summary>Alternative Windows credential.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>SMO major versions to locate.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public int[] VersionNumber { get; set; } = null!;

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private ScriptBlock? _remoteScript;

    protected override void BeginProcessing()
    {
        _remoteScript = ScriptBlock.Create(RemoteScript);
    }

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
            computers, Credential, VersionNumber, EnableException.ToBool(), _remoteScript,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string ProcessScript = """
param($ComputerName, $Credential, $VersionNumber, $EnableException, $scriptBlock, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($ComputerName, $Credential, $VersionNumber, $EnableException, $scriptBlock)

    foreach ($computer in $ComputerName.ComputerName) {
        try {
            Invoke-Command2 -ComputerName $computer -ScriptBlock $scriptBlock -Credential $Credential -ArgumentList $VersionNumber -ErrorAction Stop
        } catch {
            Stop-Function -Continue -Message "Failure" -ErrorRecord $_ -Target $computer -FunctionName Test-DbaManagementObject
        }
    }
} $ComputerName $Credential $VersionNumber $EnableException $scriptBlock @__commonParameters 3>&1 2>&1
""";

    private const string RemoteScript = """
foreach ($number in $args) {
    $smoList = (Get-ChildItem -Path "$($env:SystemRoot)\assembly\GAC_MSIL\Microsoft.SqlServer.Smo" -Filter "*$number.*" -ErrorAction SilentlyContinue | Sort-Object Name -Descending).Name
    if (-not $smoList) {
        $smoList = (Get-ChildItem -Path "$($env:SystemRoot)\Microsoft.NET\assembly\GAC_MSIL\Microsoft.SqlServer.Smo" -Filter "*$number.*" -ErrorAction SilentlyContinue | Where-Object FullName -match "_$number" | Sort-Object Name -Descending).Name
    }

    if ($smoList) {
        [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Version      = $number
            Exists       = $true
        }
    } else {
        [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Version      = $number
            Exists       = $false
        }
    }
}
""";
}


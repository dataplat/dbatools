#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes PLA data collector sets. Port of public/Remove-DbaPfDataCollectorSet.ps1
/// (W1-115). The process body rides one module-scoped PowerShell hop so the source's
/// InputObject/refetch truth gate, item-specific member reads, Test-ElevationRequirement
/// and Stop-Function dynamic continues, verbose message (including its aggregate
/// ComputerName interpolation), running-state refusal, ShouldProcess text, PLA COM delete
/// script, warning/error flow, and output shape execute with the original engine semantics.
/// The real compiled cmdlet supplies ShouldProcess; the caller's ComputerName-bound state
/// is carried explicitly because Test-Bound cannot inspect it across the module boundary.
/// Surface pinned by migration/baselines/Remove-DbaPfDataCollectorSet.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaPfDataCollectorSet", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaPfDataCollectorSetCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = BuildDefaultComputerName();

    private static DbaInstanceParameter[]? BuildDefaultComputerName()
    {
        string? name = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(name))
            return null;
        return new[] { new DbaInstanceParameter(name) };
    }

    /// <summary>Windows credential for remote operations.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>The collector-set names to remove.</summary>
    [Parameter(Position = 2)]
    [Alias("DataCollectorSet")]
    public string[]? CollectorSet { get; set; }

    /// <summary>Collector-set objects piped from Get-DbaPfDataCollectorSet.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted) { return; }
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
        }, BodyScript,
            ComputerName, Credential, CollectorSet, InputObject,
            TestBound("ComputerName"), EnableException.ToBool(), this, BoundVerbose(), BoundDebug());
    }

    /// <summary>A bound -Debug carrier for the module-scoped process body.</summary>
    private object? BoundDebug()
    {
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out object? debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    /// <summary>A bound -Verbose carrier for the module-scoped process body.</summary>
    private object? BoundVerbose()
    {
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out object? verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    private const string BodyScript = """
param($ComputerName, $Credential, $CollectorSet, $InputObject, $__computerNameBound, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($ComputerName, $Credential, $CollectorSet, $InputObject, $__computerNameBound, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $setscript = {
        $setname = $args
        $collectorset = New-Object -ComObject Pla.DataCollectorSet
        $collectorset.Query($setname, $null)
        if ($collectorset.name -eq $setname) {
            $null = $collectorset.Delete()
        } else {
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Warning "Data Collector Set $setname does not exist on $env:COMPUTERNAME."
        }
    }

    if (-not $InputObject -or ($InputObject -and $__computerNameBound)) {
        foreach ($computer in $ComputerName) {
            $InputObject += Get-DbaPfDataCollectorSet -ComputerName $computer -Credential $Credential -CollectorSet $CollectorSet
        }
    }

    if ($InputObject) {
        if (-not $InputObject.DataCollectorSetObject) {
            Stop-Function -Message "InputObject is not of the right type. Please use Get-DbaPfDataCollectorSet." -FunctionName Remove-DbaPfDataCollectorSet
            return
        }
    }

    # Check to see if its running first
    foreach ($set in $InputObject) {
        $setname = $set.Name
        $computer = $set.ComputerName
        $status = $set.State

        $null = Test-ElevationRequirement -ComputerName $computer -Continue

        Write-Message -Level Verbose -Message "$setname on $ComputerName is $status." -FunctionName Remove-DbaPfDataCollectorSet -ModuleName "dbatools"

        if ($status -eq "Running") {
            Stop-Function -Message "$setname on $computer is running. Use Stop-DbaPfDataCollectorSet to stop first." -Continue -FunctionName Remove-DbaPfDataCollectorSet
        }

        if ($__realCmdlet.ShouldProcess("$computer", "Removing collector set $setname")) {
            try {
                Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $setscript -ArgumentList $setname -ErrorAction Stop
                [PSCustomObject]@{
                    ComputerName = $computer
                    Name         = $setname
                    Status       = "Removed"
                }
            } catch {
                Stop-Function -Message "Failure Removing $setname on $computer." -ErrorRecord $_ -Target $computer -Continue -FunctionName Remove-DbaPfDataCollectorSet
            }
        }
    }
} $ComputerName $Credential $CollectorSet $InputObject $__computerNameBound $EnableException $__realCmdlet $__boundVerbose $__boundDebug 3>&1 2>&1
""";
}

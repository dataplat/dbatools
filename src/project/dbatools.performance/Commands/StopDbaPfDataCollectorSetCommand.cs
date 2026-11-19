#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Stops PLA data collector sets. Port of public/Stop-DbaPfDataCollectorSet.ps1
/// (W1-123). The process body rides one module-scoped PowerShell hop so the source's
/// InputObject/refetch truth gate, aggregate validation, item member reads, verbose text,
/// pre-ShouldProcess stopped-state continue, exact ShouldProcess action, PLA stop script,
/// warning/error flow, and final refetch execute with PowerShell semantics. The real
/// compiled cmdlet supplies ShouldProcess; caller-bound ComputerName and begin-phase NoWait
/// inversion cross the scope boundary explicitly. Surface pinned by
/// migration/baselines/Stop-DbaPfDataCollectorSet.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Stop, "DbaPfDataCollectorSet", SupportsShouldProcess = true)]
public sealed class StopDbaPfDataCollectorSetCommand : DbaBaseCmdlet
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

    /// <summary>The collector-set names to stop.</summary>
    [Parameter(Position = 2)]
    [Alias("DataCollectorSet")]
    public string[]? CollectorSet { get; set; }

    /// <summary>Collector-set objects piped from Get-DbaPfDataCollectorSet.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public object[]? InputObject { get; set; }

    /// <summary>Return without waiting for the collector set to finish stopping.</summary>
    [Parameter]
    public SwitchParameter NoWait { get; set; }

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
            TestBound("ComputerName"), !NoWait.ToBool(), EnableException.ToBool(),
            this, BoundVerbose(), BoundDebug());
    }

    private object? BoundDebug()
    {
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out object? debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    private object? BoundVerbose()
    {
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out object? verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    private const string BodyScript = """
param($ComputerName, $Credential, $CollectorSet, $InputObject, $__computerNameBound, $wait, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($ComputerName, $Credential, $CollectorSet, $InputObject, $__computerNameBound, $wait, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    #Variable marked as unused by PSScriptAnalyzer
    #$sets = @()
    $setscript = {
        $setname = $args[0]; $wait = $args[1]
        $collectorset = New-Object -ComObject Pla.DataCollectorSet
        $collectorset.Query($setname, $null)
        $null = $collectorset.Stop($wait)
    }

    if (-not $InputObject -or ($InputObject -and $__computerNameBound)) {
        foreach ($computer in $ComputerName) {
            $InputObject += Get-DbaPfDataCollectorSet -ComputerName $computer -Credential $Credential -CollectorSet $CollectorSet
        }
    }

    if ($InputObject) {
        if (-not $InputObject.DataCollectorSetObject) {
            Stop-Function -Message "InputObject is not of the right type. Please use Get-DbaPfDataCollectorSet." -FunctionName Stop-DbaPfDataCollectorSet
            return
        }
    }

    # Check to see if its running first
    foreach ($set in $InputObject) {
        $setname = $set.Name
        $computer = $set.ComputerName
        $status = $set.State

        Write-Message -Level Verbose -Message "$setname on $ComputerName is $status." -FunctionName Stop-DbaPfDataCollectorSet -ModuleName "dbatools"
        if ($status -ne "Running") {
            Stop-Function -Message "$setname on $computer is already stopped." -Continue -FunctionName Stop-DbaPfDataCollectorSet
        }
        if ($__realCmdlet.ShouldProcess($computer, "Stoping Performance Monitor collection set")) {
            try {
                Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $setscript -ArgumentList $setname, $wait -ErrorAction Stop
            } catch {
                Stop-Function -Message "Failure stopping $setname on $computer." -ErrorRecord $_ -Target $computer -Continue -FunctionName Stop-DbaPfDataCollectorSet
            }

            Get-DbaPfDataCollectorSet -ComputerName $computer -Credential $Credential -CollectorSet $setname
        }
    }
} $ComputerName $Credential $CollectorSet $InputObject $__computerNameBound $wait $EnableException $__realCmdlet $__boundVerbose $__boundDebug 3>&1 2>&1
""";
}

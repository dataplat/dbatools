#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets the output file for SQL Server Agent job steps.
/// </summary>
/// <remarks>
/// The instance connection, the job/step resolution (including the interactive Out-GridView step picker),
/// the OutputFileName assignment, the Alter, and the result-object shaping all run the original dbatools
/// PowerShell body inside the dbatools module scope rather than being reimplemented in C#, so the engine
/// decides the observable details.
///
/// The source function has NO process block - the whole body is a bare foreach over $SqlInstance, so with
/// [CmdletBinding()] it is an END block: when input is piped, ValueFromPipeline binds only the LAST item
/// and the body runs once (verified: piping a,b,c processes only c); an array -SqlInstance a,b,c runs once
/// over all three. This cmdlet reproduces that by running the hop in EndProcessing over the final bound
/// parameter values, NOT per-record in ProcessRecord. Because the whole body is a single end-block
/// invocation there is no cross-record state and no sentinel carry.
///
/// Output streams: each updated step is emitted as its Alter runs, before a later step's Alter may throw
/// terminating under -EnableException (the trailing Stop-Function has no -Continue), so buffering would
/// lose steps that were actually changed (DEF-001).
///
/// This cmdlet supplies the real ShouldProcess runtime to the hop (ConfirmImpact Medium, no -Force).
/// Surface pinned by migration/baselines/Set-DbaAgentJobOutputFile.json.
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaAgentJobOutputFile", SupportsShouldProcess = true)]
public sealed class SetDbaAgentJobOutputFileCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ValueFromPipelineByPropertyName = true, Position = 0, HelpMessage = "The SQL Server Instance")]
    [ValidateNotNull]
    [ValidateNotNullOrEmpty]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(ValueFromPipeline = true, ValueFromPipelineByPropertyName = true, HelpMessage = "SQL Credential")]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The SQL Server Agent job name whose step output files to configure.</summary>
    [Parameter]
    public object[]? Job { get; set; }

    /// <summary>Which job step(s) within the target job should have their output file configured.</summary>
    [Parameter(ValueFromPipeline = true, ValueFromPipelineByPropertyName = true, HelpMessage = "The Job Step name")]
    [ValidateNotNull]
    [ValidateNotNullOrEmpty]
    public object[]? Step { get; set; }

    /// <summary>The complete file path where SQL Agent should write job step output and error messages.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ValueFromPipelineByPropertyName = true, HelpMessage = "The Full Output File Path")]
    [ValidateNotNull]
    [ValidateNotNullOrEmpty]
    [PsStringCast]
    public string OutputFile { get; set; } = null!;

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which the
    // inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    protected override void EndProcessing()
    {
        if (Interrupted)
        {
            return;
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
        }, BodyScript,
            SqlInstance, SqlCredential, Job, Step, OutputFile, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the end block (the whole source body - it has no process block) VERBATIM apart from
    // $Pscmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess and -FunctionName Set-DbaAgentJobOutputFile on
    // the direct Stop-Function/Write-Message sites. The two early "return" statements exit the module
    // scriptblock cleanly (no sentinel to protect, so no dot-source wrap is needed).
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Job, $Step, $OutputFile, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Job, [object[]]$Step, [string]$OutputFile, $EnableException, $__realCmdlet)
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaAgentJobOutputFile
        }

        if (!$Job) {
            # This is because jobname isn't yet required
            Write-Message -Level Warning -Message "You must specify a job using the -Job parameter." -FunctionName Set-DbaAgentJobOutputFile -ModuleName "dbatools"
            return
        }

        foreach ($name in $Job) {
            $currentJob = $server.JobServer.Jobs[$name]

            if ($Step) {
                $steps = $currentJob.JobSteps | Where-Object Name -in $Step

                if (!$steps) {
                    Write-Message -Level Warning -Message "$Step didn't return any steps" -FunctionName Set-DbaAgentJobOutputFile -ModuleName "dbatools"
                    return
                }
            } else {
                if (($currentJob.JobSteps).Count -gt 1) {
                    Write-Message -Level Output -Message "Which Job Step do you wish to add output file to?" -FunctionName Set-DbaAgentJobOutputFile -ModuleName "dbatools"
                    $steps = $currentJob.JobSteps | Out-GridView -Title "Choose the Job Steps to add an output file to" -PassThru -Verbose
                } else {
                    $steps = $currentJob.JobSteps
                }
            }

            if (!$steps) {
                $steps = $currentJob.JobSteps
            }

            foreach ($jobStep in $steps) {
                $currentOutputFile = $jobStep.OutputFileName

                Write-Message -Level Verbose -Message "Current Output File for $currentJob is $currentOutputFile" -FunctionName Set-DbaAgentJobOutputFile -ModuleName "dbatools"
                Write-Message -Level Verbose -Message "Adding $OutputFile to $jobStep for $currentJob" -FunctionName Set-DbaAgentJobOutputFile -ModuleName "dbatools"

                try {
                    if ($__realCmdlet.ShouldProcess($jobStep, "Changing Output File from $currentOutputFile to $OutputFile")) {
                        $jobStep.OutputFileName = $OutputFile
                        $jobStep.Alter()
                        $jobStep.Refresh()

                        [PSCustomObject]@{
                            ComputerName      = $server.ComputerName
                            InstanceName      = $server.ServiceName
                            SqlInstance       = $server.DomainInstanceName
                            Job               = $currentJob.Name
                            JobStep           = $jobStep.Name
                            OutputFileName    = $OutputFile
                            OldOutputFileName = $currentOutputFile
                        }
                    }
                } catch {
                    Stop-Function -Message "Failed to add $OutputFile to $jobStep for $currentJob" -InnerErrorRecord $_ -Target $currentJob -FunctionName Set-DbaAgentJobOutputFile
                }
            }
        }
    }
} $SqlInstance $SqlCredential $Job $Step $OutputFile $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}

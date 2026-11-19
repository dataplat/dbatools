#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoServer = Microsoft.SqlServer.Management.Smo.Server;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Modifies (or, with -Force, creates) a SQL Server Agent job step.
/// </summary>
/// <remarks>
/// The step-id validation, the instance connection, the job/step resolution, the optional step creation, the
/// property assignments, the Alter, and the output all run the original dbatools PowerShell body inside the
/// dbatools module scope rather than being reimplemented in C#, so the engine decides the observable details.
///
/// The function has begin/process/end blocks. The begin block runs one-shot OnSuccessStepId / OnFailStepId /
/// Subsystem-server validations whose no-Continue Stop-Functions set the function-scope interrupt and return.
/// Both the process AND the end blocks then short-circuit via Test-FunctionInterrupt, so the interrupt is
/// carried begin -> (process, end) via the C# field: the begin hop reads it with Get-Variable -Scope 0 after
/// a dot-sourced body and reports it in a sentinel, and BOTH ProcessRecord and EndProcessing guard on it.
/// The process Stop-Functions are all -Continue (which never sets the interrupt), so the process hop never
/// re-reports it. Under -EnableException the begin Stop-Functions throw instead, terminating before any record.
///
/// The begin block's "if (\$Force) { \$ConfirmPreference = 'none' }" is folded into the top of the process hop
/// with \$__gate = if (\$Force) { \$PSCmdlet } else { \$__realCmdlet }; both ShouldProcess sites route through
/// \$__gate. -Force is also read by value (the add-or-get-step branch). The three Test-Bound sites become
/// \$__bound.ContainsKey lookups on this cmdlet's own bound parameters. \$jobStep is always freshly assigned
/// before use (create branch or existing branch, else the iteration continues), so it does not leak.
///
/// Output streams: each altered step is emitted before a later one may fail under -EnableException (DEF-001).
/// This cmdlet supplies the real ShouldProcess runtime (ConfirmImpact Low). Surface pinned by
/// migration/baselines/Set-DbaAgentJobStep.json.
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaAgentJobStep", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class SetDbaAgentJobStepCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The job(s) whose step to modify.</summary>
    [Parameter(Position = 2)]
    public object[]? Job { get; set; }

    /// <summary>The name of the job step to modify.</summary>
    [Parameter(Position = 3)]
    public string? StepName { get; set; }

    /// <summary>A new name for the job step.</summary>
    [Parameter(Position = 4)]
    public string? NewName { get; set; }

    /// <summary>The subsystem used by the job step.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    [ValidateSet("ActiveScripting", "AnalysisCommand", "AnalysisQuery", "CmdExec", "Distribution", "LogReader", "Merge", "PowerShell", "QueueReader", "Snapshot", "Ssis", "TransactSql")]
    public string? Subsystem { get; set; }

    /// <summary>The subsystem server for the job step.</summary>
    [Parameter(Position = 6)]
    public string? SubsystemServer { get; set; }

    /// <summary>The command to be executed by the job step.</summary>
    [Parameter(Position = 7)]
    public string? Command { get; set; }

    /// <summary>The command execution success code.</summary>
    [Parameter(Position = 8)]
    public int CmdExecSuccessCode { get; set; }

    /// <summary>The action to take on success.</summary>
    [Parameter(Position = 9)]
    [PsStringCast]
    [ValidateSet("QuitWithSuccess", "QuitWithFailure", "GoToNextStep", "GoToStep")]
    public string? OnSuccessAction { get; set; }

    /// <summary>The step id to go to on success.</summary>
    [Parameter(Position = 10)]
    public int OnSuccessStepId { get; set; }

    /// <summary>The action to take on failure.</summary>
    [Parameter(Position = 11)]
    [PsStringCast]
    [ValidateSet("QuitWithSuccess", "QuitWithFailure", "GoToNextStep", "GoToStep")]
    public string? OnFailAction { get; set; }

    /// <summary>The step id to go to on failure.</summary>
    [Parameter(Position = 12)]
    public int OnFailStepId { get; set; }

    /// <summary>The database for the job step.</summary>
    [Parameter(Position = 13)]
    public string? Database { get; set; }

    /// <summary>The database user for the job step.</summary>
    [Parameter(Position = 14)]
    public string? DatabaseUser { get; set; }

    /// <summary>The number of retry attempts.</summary>
    [Parameter(Position = 15)]
    public int RetryAttempts { get; set; }

    /// <summary>The retry interval.</summary>
    [Parameter(Position = 16)]
    public int RetryInterval { get; set; }

    /// <summary>The output file name for the job step.</summary>
    [Parameter(Position = 17)]
    public string? OutputFileName { get; set; }

    /// <summary>The job step flag(s).</summary>
    [Parameter(Position = 18)]
    [ValidateSet("AppendAllCmdExecOutputToJobHistory", "AppendToJobHistory", "AppendToLogFile", "AppendToTableLog", "LogToTableWithOverwrite", "None", "ProvideStopProcessEvent")]
    public string[]? Flag { get; set; }

    /// <summary>The proxy name for the job step.</summary>
    [Parameter(Position = 19)]
    public string? ProxyName { get; set; }

    /// <summary>SMO Server objects piped in.</summary>
    [Parameter(Position = 20, ValueFromPipeline = true)]
    public SmoServer[]? InputObject { get; set; }

    /// <summary>Create the job step if it does not exist.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which the
    // inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    // The function-scope interrupt set by the begin validations; carried to guard both the process records
    // and the end block (both check Test-FunctionInterrupt in the source).
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            SqlInstance, OnSuccessAction, OnSuccessStepId, OnFailAction, OnFailStepId, Subsystem, SubsystemServer,
            EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__setDbaAgentJobStepBegin"))
            {
                if (sentinel["__setDbaAgentJobStepBegin"] is Hashtable state)
                {
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                }
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _interrupted)
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
        }, ProcessScript,
            SqlInstance, SqlCredential, Job, StepName, NewName, Subsystem, SubsystemServer, Command,
            CmdExecSuccessCode, OnSuccessAction, OnSuccessStepId, OnFailAction, OnFailStepId, Database,
            DatabaseUser, RetryAttempts, RetryInterval, OutputFileName, Flag, ProxyName, Force.ToBool(),
            InputObject, EnableException.ToBool(), new Hashtable(MyInvocation.BoundParameters), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
    {
        if (Interrupted || _interrupted)
        {
            return;
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, EndScript,
            EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    // PS: the begin block VERBATIM apart from -FunctionName Set-DbaAgentJobStep on the direct Stop-Functions.
    // The "if (\$Force) { \$ConfirmPreference = 'none' }" line is folded into the process hop. Dot-sourced so
    // the validation returns still emit the interrupt sentinel.
    private const string BeginScript = """
param($SqlInstance, $OnSuccessAction, $OnSuccessStepId, $OnFailAction, $OnFailStepId, $Subsystem, $SubsystemServer, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [string]$OnSuccessAction, [int]$OnSuccessStepId, [string]$OnFailAction, [int]$OnFailStepId, [string]$Subsystem, [string]$SubsystemServer, $EnableException)
    . {
        # Check the parameter on success step id
        if (($OnSuccessAction -ne 'GoToStep') -and ($OnSuccessStepId -ge 1)) {
            Stop-Function -Message "Parameter OnSuccessStepId can only be used with OnSuccessAction 'GoToStep'." -Target $SqlInstance -FunctionName Set-DbaAgentJobStep
            return
        }

        # Check the parameter on fail step id
        if (($OnFailAction -ne 'GoToStep') -and ($OnFailStepId -ge 1)) {
            Stop-Function -Message "Parameter OnFailStepId can only be used with OnFailAction 'GoToStep'." -Target $SqlInstance -FunctionName Set-DbaAgentJobStep
            return
        }

        if ($Subsystem -in 'AnalysisScripting', 'AnalysisCommand', 'AnalysisQuery') {
            if (-not $SubsystemServer) {
                Stop-Function -Message "Please enter the server value using -SubSystemServer for subsystem $Subsystem." -Target $Subsystem -FunctionName Set-DbaAgentJobStep
                return
            }
        }
    }
    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __setDbaAgentJobStepBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $SqlInstance $OnSuccessAction $OnSuccessStepId $OnFailAction $OnFailStepId $Subsystem $SubsystemServer $EnableException @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM apart from $PSCmdlet.ShouldProcess -> $__gate.ShouldProcess, the three
    // Test-Bound sites -> $__bound.ContainsKey, and -FunctionName Set-DbaAgentJobStep on the direct
    // Stop-Function/Write-Message sites. The begin Force/ConfirmPreference line + gate selection are prepended.
    // The Test-FunctionInterrupt check is preserved verbatim but inert (the C# guard already short-circuits an
    // interrupted record); the process Stop-Functions are all -Continue so no interrupt is set here.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Job, $StepName, $NewName, $Subsystem, $SubsystemServer, $Command, $CmdExecSuccessCode, $OnSuccessAction, $OnSuccessStepId, $OnFailAction, $OnFailStepId, $Database, $DatabaseUser, $RetryAttempts, $RetryInterval, $OutputFileName, $Flag, $ProxyName, $Force, $InputObject, $EnableException, $__bound, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Job, [string]$StepName, [string]$NewName, [string]$Subsystem, [string]$SubsystemServer, [string]$Command, [int]$CmdExecSuccessCode, [string]$OnSuccessAction, [int]$OnSuccessStepId, [string]$OnFailAction, [int]$OnFailStepId, [string]$Database, [string]$DatabaseUser, [int]$RetryAttempts, [int]$RetryInterval, [string]$OutputFileName, [string[]]$Flag, [string]$ProxyName, $Force, [Microsoft.SqlServer.Management.Smo.Server[]]$InputObject, $EnableException, $__bound, $__realCmdlet)
    if ($Force) { $ConfirmPreference = 'none' }
    $__gate = if ($Force) { $PSCmdlet } else { $__realCmdlet }

    if (Test-FunctionInterrupt) { return }

    # gather the SqlInstance(s) and pipeline of connected instances
    foreach ($instance in $SqlInstance) {
        try {
            $InputObject += Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaAgentJobStep
        }
    }

    foreach ($server in $InputObject) {

        if ($Subsystem -eq "ActiveScripting" -and $server.VersionMajor -ge 13) {
            Stop-Function -Message "ActiveScripting (ActiveX script) is not supported in SQL Server 2016 or higher" -Target $server -Continue -FunctionName Set-DbaAgentJobStep
        }

        foreach ($j in $Job) {
            try {
                $currentJob = $server.JobServer.Jobs[$j]

                if (-not $currentJob) {
                    Stop-Function -Message "Job '$j' doesn't exist on $server" -Target $server -Continue -FunctionName Set-DbaAgentJobStep
                }

                $currentJobStep = $currentJob.JobSteps | Where-Object Name -eq $StepName

                if (-not $Force -and (-not $currentJobStep)) {
                    Stop-Function -Message "Step '$StepName' doesn't exist for job $j on $server. If you would like to add a new job step use -Force" -Target $server -Continue -FunctionName Set-DbaAgentJobStep
                } elseif ($Force -and (-not $currentJobStep)) {
                    Write-Message -Message "Adding job step $StepName to $($currentJob.Name) on $server" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"

                    try {
                        # create the job step as a placeholder here and then the other fields will be updated below depending on what the caller specified
                        $jobStep = New-DbaAgentJobStep -SqlInstance $server -Job $currentJob -StepName $StepName -EnableException
                    } catch {
                        Stop-Function -Message "Something went wrong creating the job step" -Target $server -ErrorRecord $_ -Continue -FunctionName Set-DbaAgentJobStep
                    }

                } else {
                    $jobStep = $currentJobStep
                }

                Write-Message -Message "Modifying job '$j' on $server" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"

                #region job step options
                # Setting the options for the job step
                if ($NewName) {
                    if ($__gate.ShouldProcess($server, "Setting job step name to $NewName for $StepName")) {
                        $jobStep.Rename($NewName)
                    }
                }

                if ($Subsystem) {
                    Write-Message -Message "Setting job step subsystem to $Subsystem" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
                    $jobStep.Subsystem = $Subsystem
                }

                if ($SubsystemServer) {
                    Write-Message -Message "Setting job step subsystem server to $SubsystemServer" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
                    $jobStep.Server = $SubsystemServer
                }

                if ($Command) {
                    Write-Message -Message "Setting job step command to $Command" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
                    $jobStep.Command = $Command
                }

                if ($CmdExecSuccessCode) {
                    Write-Message -Message "Setting job step command exec success code to $CmdExecSuccessCode" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
                    $jobStep.CommandExecutionSuccessCode = $CmdExecSuccessCode
                }

                if ($OnSuccessAction) {
                    Write-Message -Message "Setting job step success action to $OnSuccessAction" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
                    $jobStep.OnSuccessAction = $OnSuccessAction
                }

                if ($OnSuccessStepId) {
                    Write-Message -Message "Setting job step success step id to $OnSuccessStepId" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
                    $jobStep.OnSuccessStep = $OnSuccessStepId
                }

                if ($OnFailAction) {
                    Write-Message -Message "Setting job step fail action to $OnFailAction" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
                    $jobStep.OnFailAction = $OnFailAction
                }

                if ($OnFailStepId) {
                    Write-Message -Message "Setting job step fail step id to $OnFailStepId" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
                    $jobStep.OnFailStep = $OnFailStepId
                }

                if ($Database) {
                    # Check if the database is present on the server
                    if ($server.Databases.Name -contains $Database) {
                        Write-Message -Message "Setting job step database name to $Database" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
                        $jobStep.DatabaseName = $Database
                    } else {
                        Stop-Function -Message "The database $Database is not present on $server." -Target $server -Continue -FunctionName Set-DbaAgentJobStep
                    }
                }

                if (($DatabaseUser) -and ($Database)) {
                    # Check if the username is present in the database
                    if ($Server.Databases[$jobStep.DatabaseName].Users.Name -contains $DatabaseUser) {
                        Write-Message -Message "Setting job step database username to $DatabaseUser" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
                        $jobStep.DatabaseUserName = $DatabaseUser
                    } else {
                        Stop-Function -Message "The database user '$DatabaseUser' is not present in the database $($jobStep.DatabaseName) on $server." -Target $server -Continue -FunctionName Set-DbaAgentJobStep
                    }
                }

                if ($__bound.ContainsKey('RetryAttempts')) {
                    Write-Message -Message "Setting job step retry attempts to $RetryAttempts" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
                    $jobStep.RetryAttempts = $RetryAttempts
                }

                if ($__bound.ContainsKey('RetryInterval')) {
                    Write-Message -Message "Setting job step retry interval to $RetryInterval" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
                    $jobStep.RetryInterval = $RetryInterval
                }

                if ($OutputFileName) {
                    Write-Message -Message "Setting job step output file name to $OutputFileName" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
                    $jobStep.OutputFileName = $OutputFileName
                }

                if ($__bound.ContainsKey('ProxyName')) {
                    if ([string]::IsNullOrEmpty($ProxyName)) {
                        # Remove proxy from job step
                        Write-Message -Message "Removing proxy from job step" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
                        $jobStep.ProxyName = ''
                    } elseif ($Server.JobServer.ProxyAccounts.Name -contains $ProxyName) {
                        # Set or update proxy name
                        Write-Message -Message "Setting job step proxy name to $ProxyName" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
                        $jobStep.ProxyName = $ProxyName
                    } else {
                        Stop-Function -Message "The proxy name $ProxyName doesn't exist on instance $server." -Target $server -Continue -FunctionName Set-DbaAgentJobStep
                    }
                }

                if ($Flag.Count -ge 1) {
                    Write-Message -Message "Setting job step flag(s) to $($Flags -join ',')" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
                    $jobStep.JobStepFlags = $Flag
                }
                #region job step options

                # Execute
                if ($__gate.ShouldProcess($server, "Committing changes for job step '$StepName' for job '$j'")) {
                    try {
                        Write-Message -Message "Committing changes for '$StepName' for job '$j' on $server" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"

                        # Change the job step
                        $jobStep.Alter()

                        # Return the job step
                        $jobStep
                    } catch {
                        Stop-Function -Message "Something went wrong changing the job step" -ErrorRecord $_ -Target $server -Continue -FunctionName Set-DbaAgentJobStep
                    }
                }

            } catch {
                Stop-Function -Message "Something went wrong" -Target $j -ErrorRecord $_ -Continue -FunctionName Set-DbaAgentJobStep
            }
        }
    }
} $SqlInstance $SqlCredential $Job $StepName $NewName $Subsystem $SubsystemServer $Command $CmdExecSuccessCode $OnSuccessAction $OnSuccessStepId $OnFailAction $OnFailStepId $Database $DatabaseUser $RetryAttempts $RetryInterval $OutputFileName $Flag $ProxyName $Force $InputObject $EnableException $__bound $__realCmdlet @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM apart from -FunctionName Set-DbaAgentJobStep on the direct Write-Message.
    // The Test-FunctionInterrupt check is preserved verbatim but inert (the C# EndProcessing guard already
    // short-circuits an interrupted pipeline). $EnableException is marshaled in for the scope-walk + a
    // positional arg.
    private const string EndScript = """
param($EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($EnableException)
    if (Test-FunctionInterrupt) { return }
    Write-Message -Message "Finished changing job step(s)" -Level Verbose -FunctionName Set-DbaAgentJobStep -ModuleName "dbatools"
} $EnableException @__commonParameters 3>&1 2>&1
""";
}

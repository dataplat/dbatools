#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a SQL Server Agent job step on the target instances.
/// </summary>
/// <remarks>
/// The operator-requirement validation, the SMO job-step construction with its option assignments, the
/// step-id insertion/removal logic, and the output all run the original dbatools PowerShell body inside
/// the dbatools module scope rather than being reimplemented in C#, so the engine decides the observable
/// details.
///
/// This function has begin, process, and end blocks that cannot be collapsed. The begin block validates
/// three parameter combinations with a Stop-Function that sets the function-scope interrupt; those
/// warnings are observable and empty-pipeline input runs begin and end but skips process, so the begin
/// is its own module-scope hop. The interrupt does not survive between separate hops on its own, so the
/// begin hop reads the flag at Get-Variable -Scope 0 after a dot-sourced body and reports it in a
/// sentinel; the C# then skips the process and end hops. Every process Stop-Function uses -Continue, so
/// the process never sets the interrupt - only a begin gate does.
///
/// The begin block also lowers the confirm preference under -Force; across hops the process scope is
/// separate, so it is re-established at the process hop top and the ShouldProcess gate selects $PSCmdlet
/// (whose confirm preference is lowered) under -Force and the real cmdlet otherwise, so a bound -Confirm
/// cannot be overridden on the real cmdlet's own runtime.
///
/// StepName is a single variable in the source's shared process scope: the "-StepId -Force" branch
/// reassigns it (to the id-1 step's name) and later records read the reassigned value. A per-record hop
/// scope would lose that, so the process hop carries StepName across records via a sentinel, reproducing
/// the shared-scope behavior. (The source also reads an undeclared $Flags in one verbose message - a
/// source typo for $Flag that always renders empty - which is preserved verbatim.)
///
/// Process output streams as it is produced. A single record can create steps across several instances
/// or jobs, and each created step is emitted before a later one may fail under -EnableException;
/// buffering them and losing them to a later terminating failure would hide steps that were created.
///
/// This cmdlet supplies the real ShouldProcess runtime to the process hop. Surface pinned by
/// migration/baselines/New-DbaAgentJobStep.json.
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaAgentJobStep", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaAgentJobStepCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The job or jobs to add the step to.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [ValidateNotNullOrEmpty]
    public object[] Job { get; set; } = null!;

    /// <summary>The step id for the job step.</summary>
    [Parameter(Position = 3)]
    public int StepId { get; set; }

    /// <summary>The name of the job step.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    [ValidateNotNullOrEmpty]
    [PsStringCast]
    public string StepName { get; set; } = null!;

    /// <summary>The subsystem used by the job step.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    [ValidateSet("ActiveScripting", "AnalysisCommand", "AnalysisQuery", "CmdExec", "Distribution", "LogReader", "Merge", "PowerShell", "QueueReader", "Snapshot", "Ssis", "TransactSql")]
    public string Subsystem { get; set; } = "TransactSql";

    /// <summary>The subsystem server.</summary>
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
    public string OnSuccessAction { get; set; } = "QuitWithSuccess";

    /// <summary>The step id to go to on success.</summary>
    [Parameter(Position = 10)]
    public int OnSuccessStepId { get; set; }

    /// <summary>The action to take on failure.</summary>
    [Parameter(Position = 11)]
    [PsStringCast]
    [ValidateSet("QuitWithFailure", "QuitWithSuccess", "GoToNextStep", "GoToStep")]
    public string OnFailAction { get; set; } = "QuitWithFailure";

    /// <summary>The step id to go to on failure.</summary>
    [Parameter(Position = 12)]
    public int OnFailStepId { get; set; }

    /// <summary>The database the job step runs against.</summary>
    [Parameter(Position = 13)]
    public string? Database { get; set; }

    /// <summary>The database user the job step runs as.</summary>
    [Parameter(Position = 14)]
    public string? DatabaseUser { get; set; }

    /// <summary>The number of retry attempts.</summary>
    [Parameter(Position = 15)]
    public int RetryAttempts { get; set; }

    /// <summary>The retry interval in minutes.</summary>
    [Parameter(Position = 16)]
    public int RetryInterval { get; set; }

    /// <summary>The output file name for the job step.</summary>
    [Parameter(Position = 17)]
    public string? OutputFileName { get; set; }

    /// <summary>The job step logging flags.</summary>
    [Parameter(Position = 18)]
    [ValidateSet("AppendAllCmdExecOutputToJobHistory", "AppendToJobHistory", "AppendToLogFile", "AppendToTableLog", "LogToTableWithOverwrite", "None", "ProvideStopProcessEvent")]
    public string[]? Flag { get; set; }

    /// <summary>The proxy account the job step runs under.</summary>
    [Parameter(Position = 19)]
    public string? ProxyName { get; set; }

    /// <summary>Insert the step at the given step id, shifting later steps down.</summary>
    [Parameter]
    public SwitchParameter Insert { get; set; }

    /// <summary>Overwrite an existing step with the same name or id.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The function-scope interrupt: set only by a begin validation gate (every process Stop-Function is
    // -Continue). It halts the process and end hops.
    private bool _interrupted;
    // StepName carried across process records: the source reassigns it in the -StepId -Force branch and
    // later records read the reassigned value through the shared scope. The reassignment can legitimately
    // yield null (no step has id 1), so the carried value is tracked with a separate flag rather than a
    // null sentinel - null-once-carried must win over the originally bound StepName.
    private bool _stepNameCarried;
    private string? _stepName;

    protected override void BeginProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            SqlInstance, OnSuccessAction, OnSuccessStepId, OnFailAction, OnFailStepId,
            Subsystem, SubsystemServer, Force.ToBool(), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaAgentJobStepBegin"))
            {
                if (sentinel["__newDbaAgentJobStepBegin"] is Hashtable state)
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

        // First record uses the bound StepName; later records use the value the previous record left
        // (which may legitimately be null - hence the flag, not a null-coalesce).
        string? stepNameForThisRecord = _stepNameCarried ? _stepName : StepName;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaAgentJobStepProcess"))
            {
                if (sentinel["__newDbaAgentJobStepProcess"] is Hashtable state)
                {
                    _stepName = state["StepName"] as string;
                    _stepNameCarried = true;
                }
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
            SqlInstance, SqlCredential, Job, StepId, stepNameForThisRecord, Subsystem, SubsystemServer,
            Command, CmdExecSuccessCode, OnSuccessAction, OnSuccessStepId, OnFailAction, OnFailStepId,
            Database, DatabaseUser, RetryAttempts, RetryInterval, OutputFileName, Insert.ToBool(),
            Flag, ProxyName, Force.ToBool(), EnableException.ToBool(), this,
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
            EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
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

    // PS: the begin block. The three validation gates run dot-sourced so a "+ return" exits only the
    // block, then the interrupt flag is read at Get-Variable -Scope 0 and reported. Edit: -FunctionName
    // New-DbaAgentJobStep on the direct Stop-Function sites.
    private const string BeginScript = """
param($SqlInstance, $OnSuccessAction, $OnSuccessStepId, $OnFailAction, $OnFailStepId, $Subsystem, $SubsystemServer, $Force, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [string]$OnSuccessAction, [int]$OnSuccessStepId, [string]$OnFailAction, [int]$OnFailStepId, [string]$Subsystem, [string]$SubsystemServer, $Force, $EnableException)

    . {
        if ($Force) { $ConfirmPreference = 'none' }

        # Check the parameter on success step id
        if (($OnSuccessAction -ne 'GoToStep') -and ($OnSuccessStepId -ge 1)) {
            Stop-Function -Message "Parameter OnSuccessStepId can only be used with OnSuccessAction 'GoToStep'." -Target $SqlInstance -FunctionName New-DbaAgentJobStep
            return
        }

        # Check the parameter on fail step id
        if (($OnFailAction -ne 'GoToStep') -and ($OnFailStepId -ge 1)) {
            Stop-Function -Message "Parameter OnFailStepId can only be used with OnFailAction 'GoToStep'." -Target $SqlInstance -FunctionName New-DbaAgentJobStep
            return
        }

        if ($Subsystem -in 'AnalysisScripting', 'AnalysisCommand', 'AnalysisQuery') {
            if (-not $SubsystemServer) {
                Stop-Function -Message "Please enter the server value using -SubSystemServer for subsystem $Subsystem." -Target $Subsystem -FunctionName New-DbaAgentJobStep
                return
            }
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __newDbaAgentJobStepBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $SqlInstance $OnSuccessAction $OnSuccessStepId $OnFailAction $OnFailStepId $Subsystem $SubsystemServer $Force $EnableException @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM, dot-sourced so the (dead-in-hop) top interrupt check cannot skip
    // the StepName sentinel. Edits: $PSCmdlet.ShouldProcess -> $__gate.ShouldProcess (the gate selector
    // re-establishes the begin's -Force confirm lowering in this separate scope), and -FunctionName
    // New-DbaAgentJobStep on the direct Stop-Function/Write-Message sites. StepName is carried in and the
    // possibly-reassigned value is reported out for the next record.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Job, $StepId, $StepName, $Subsystem, $SubsystemServer, $Command, $CmdExecSuccessCode, $OnSuccessAction, $OnSuccessStepId, $OnFailAction, $OnFailStepId, $Database, $DatabaseUser, $RetryAttempts, $RetryInterval, $OutputFileName, $Insert, $Flag, $ProxyName, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Job, [int]$StepId, [string]$StepName, [string]$Subsystem, [string]$SubsystemServer, [string]$Command, [int]$CmdExecSuccessCode, [string]$OnSuccessAction, [int]$OnSuccessStepId, [string]$OnFailAction, [int]$OnFailStepId, [string]$Database, [string]$DatabaseUser, [int]$RetryAttempts, [int]$RetryInterval, [string]$OutputFileName, $Insert, [string[]]$Flag, [string]$ProxyName, $Force, $EnableException, $__realCmdlet)

    if ($Force) { $ConfirmPreference = 'none' }
    $__gate = if ($Force) { $PSCmdlet } else { $__realCmdlet }

    . {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $Server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaAgentJobStep
            }

            foreach ($j in $Job) {

                # Check if the job exists
                if ($Server.JobServer.Jobs.Name -notcontains $j) {
                    Write-Message -Message "Job $j doesn't exist on $instance" -Level Warning -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                } else {
                    # Create the job step object
                    try {
                        # Get the job from the server again since fields on the job object may have changed
                        $currentJob = $Server.JobServer.Jobs[$j]

                        # Create the job step
                        $jobStep = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep

                        # Set the job where the job steps belongs to
                        $jobStep.Parent = $currentJob
                    } catch {
                        if ($_.Exception.Message -match "newParent") {
                            Stop-Function -Message "Cannot create agent job step through a contained availability group listener. SQL Server Agent objects are instance-level and must be managed on the instance directly. Please connect to the primary replica instead of the listener. Use Get-DbaAvailabilityGroup to find the current primary replica." -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaAgentJobStep
                        } else {
                            Stop-Function -Message "Something went wrong creating the job step" -Target $instance -ErrorRecord $_ -Continue -FunctionName New-DbaAgentJobStep
                        }
                    }

                    #region job step options
                    # Setting the options for the job step
                    if ($StepName) {
                        # Check if the step already exists
                        if ($currentJob.JobSteps.Name -notcontains $StepName) {
                            $jobStep.Name = $StepName
                        } elseif (($currentJob.JobSteps.Name -contains $StepName) -and $Force) {
                            Write-Message -Message "Step $StepName already exists for job. Force is used. Removing existing step" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"

                            # Remove the job step based on the name
                            Remove-DbaAgentJobStep -SqlInstance $instance -Job $currentJob -StepName $StepName -SqlCredential $SqlCredential -Confirm:$false

                            # Set the name job step object
                            $jobStep.Name = $StepName
                        } else {
                            Stop-Function -Message "The step name $StepName already exists for job $currentJob" -Target $instance -Continue -FunctionName New-DbaAgentJobStep
                        }
                    }

                    # If the step id need to be set
                    if ($StepId) {
                        # Check if the used step id is already in place
                        if ($currentJob.JobSteps.ID -notcontains $StepId) {
                            Write-Message -Message "Setting job step step id to $StepId" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                            $jobStep.ID = $StepId
                        } elseif (($currentJob.JobSteps.ID -contains $StepID) -and $Insert) {
                            Write-Message -Message "Inserting step as step $StepID" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                            foreach ($tStep in $currentJob.JobSteps) {
                                if ($tStep.Id -ge $Stepid) {
                                    $tStep.Id = ($tStep.ID) + 1
                                }
                                if ($tStep.OnFailureStepID -ge $StepId -and $tStep.OnFailureStepId -ne 0) {
                                    $tStep.OnFailureStepID = ($tStep.OnFailureStepID) + 1
                                }
                            }
                            $jobStep.ID = $StepId
                        } elseif (($currentJob.JobSteps.ID -contains $StepId) -and $Force) {
                            Write-Message -Message "Step ID $StepId already exists for job. Force is used. Removing existing step" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"

                            # Remove the existing job step
                            $StepName = ($currentJob.JobSteps | Where-Object { $_.ID -eq 1 }).Name
                            Remove-DbaAgentJobStep -SqlInstance $instance -Job $currentJob -StepName $StepName -SqlCredential $SqlCredential -Confirm:$false

                            # Set the ID job step object
                            $jobStep.ID = $StepId
                        } else {
                            Stop-Function -Message "The step id $StepId already exists for job $currentJob" -Target $instance -Continue -FunctionName New-DbaAgentJobStep
                        }
                    } else {
                        # Get the job step count
                        $jobStep.ID = $currentJob.JobSteps.Count + 1
                    }

                    if ($Subsystem) {
                        Write-Message -Message "Setting job step subsystem to $Subsystem" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                        $jobStep.Subsystem = $Subsystem
                    }

                    if ($SubsystemServer) {
                        Write-Message -Message "Setting job step subsystem server to $SubsystemServer" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                        $jobStep.Server = $SubsystemServer
                    }

                    if ($Command) {
                        Write-Message -Message "Setting job step command to $Command" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                        $jobStep.Command = $Command
                    }

                    if ($CmdExecSuccessCode) {
                        Write-Message -Message "Setting job step command exec success code to $CmdExecSuccessCode" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                        $jobStep.CommandExecutionSuccessCode = $CmdExecSuccessCode
                    }

                    if ($OnSuccessAction) {
                        Write-Message -Message "Setting job step success action to $OnSuccessAction" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                        $jobStep.OnSuccessAction = $OnSuccessAction
                    }

                    if ($OnSuccessStepId) {
                        Write-Message -Message "Setting job step success step id to $OnSuccessStepId" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                        $jobStep.OnSuccessStep = $OnSuccessStepId
                    }

                    if ($OnFailAction) {
                        Write-Message -Message "Setting job step fail action to $OnFailAction" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                        $jobStep.OnFailAction = $OnFailAction
                    }

                    if ($OnFailStepId) {
                        Write-Message -Message "Setting job step fail step id to $OnFailStepId" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                        $jobStep.OnFailStep = $OnFailStepId
                    }

                    if ($Database) {
                        # Check if the database is present on the server
                        if ($Server.Databases.Name -contains $Database) {
                            Write-Message -Message "Setting job step database name to $Database" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                            $jobStep.DatabaseName = $Database
                        } else {
                            Stop-Function -Message "The database is not present on instance $instance." -Target $instance -Continue -FunctionName New-DbaAgentJobStep
                        }
                    }

                    if ($DatabaseUser -and $Database) {
                        # Check if the username is present in the database
                        if ($Server.Databases[$Database].Users.Name -contains $DatabaseUser) {

                            Write-Message -Message "Setting job step database username to $DatabaseUser" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                            $jobStep.DatabaseUserName = $DatabaseUser
                        } else {
                            Stop-Function -Message "The database user is not present in the database $Database on instance $instance." -Target $instance -Continue -FunctionName New-DbaAgentJobStep
                        }
                    }

                    if ($RetryAttempts) {
                        Write-Message -Message "Setting job step retry attempts to $RetryAttempts" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                        $jobStep.RetryAttempts = $RetryAttempts
                    }

                    if ($RetryInterval) {
                        Write-Message -Message "Setting job step retry interval to $RetryInterval" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                        $jobStep.RetryInterval = $RetryInterval
                    }

                    if ($OutputFileName) {
                        Write-Message -Message "Setting job step output file name to $OutputFileName" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                        $jobStep.OutputFileName = $OutputFileName
                    }

                    if ($ProxyName) {
                        # Check if the proxy exists
                        if ($Server.JobServer.ProxyAccounts.Name -contains $ProxyName) {
                            Write-Message -Message "Setting job step proxy name to $ProxyName" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                            $jobStep.ProxyName = $ProxyName
                        } else {
                            Stop-Function -Message "The proxy name $ProxyName doesn't exist on instance $instance." -Target $instance -Continue -FunctionName New-DbaAgentJobStep
                        }
                    }

                    if ($Flag.Count -ge 1) {
                        Write-Message -Message "Setting job step flag(s) to $($Flags -join ',')" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
                        $jobStep.JobStepFlags = $Flag
                    }
                    #endregion job step options

                    # Execute
                    if ($__gate.ShouldProcess($instance, "Creating the job step $StepName")) {
                        try {
                            Write-Message -Message "Creating the job step" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"

                            # Create the job step
                            $jobStep.Create()
                            $currentJob.Alter()
                        } catch {
                            Stop-Function -Message "Something went wrong creating the job step" -Target $instance -ErrorRecord $_ -Continue -FunctionName New-DbaAgentJobStep
                        }

                        # Return the job step
                        $jobStep
                    }
                }
            } # foreach object job
        } # foreach object instance
    }

    @{ __newDbaAgentJobStepProcess = @{ StepName = $StepName } }
} $SqlInstance $SqlCredential $Job $StepId $StepName $Subsystem $SubsystemServer $Command $CmdExecSuccessCode $OnSuccessAction $OnSuccessStepId $OnFailAction $OnFailStepId $Database $DatabaseUser $RetryAttempts $RetryInterval $OutputFileName $Insert $Flag $ProxyName $Force $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";

    // PS: the end block. It only runs when the begin did not set the interrupt (the C# guards that), so
    // the Test-FunctionInterrupt check is preserved for fidelity but never fires here. Edit: -FunctionName
    // New-DbaAgentJobStep on the direct Write-Message. EnableException is in scope in the source end block
    // (shared function scope); carrying it keeps the hop a well-formed positional pass.
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
    Write-Message -Message "Finished creating job step(s)" -Level Verbose -FunctionName New-DbaAgentJobStep -ModuleName "dbatools"
} $EnableException @__commonParameters 3>&1 2>&1
""";
}

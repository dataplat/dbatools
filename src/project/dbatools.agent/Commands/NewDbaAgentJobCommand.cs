#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a SQL Server Agent job on the target instances.
/// </summary>
/// <remarks>
/// The notification-level normalization, the operator-requirement validation, the SMO job
/// construction with its option assignments, the category/owner/notification wiring, and the output
/// all run the original dbatools PowerShell body inside the dbatools module scope rather than being
/// reimplemented in C#, so the engine decides the observable details.
///
/// This function has a begin, a process, and an end block, and the three cannot be collapsed into one
/// hop. The begin block validates the operator requirements (a "-EmailLevel without -EmailOperator"
/// style gate) with a Stop-Function that sets the function-scope interrupt; those warnings are
/// observable, and an empty-array pipeline (@() | New-DbaAgentJob) runs begin and end but skips
/// process, so folding the begin into the process hop would either lose the warning on empty input or
/// duplicate it per record. So begin, process, and end are each their own module-scope hop.
///
/// The interrupt does not survive between hops on its own - Stop-Function writes its flag at the
/// caller scope, and each hop is a separate module-scope invocation - so each hop reads the flag at
/// Get-Variable -Scope 0 after a dot-sourced body and reports it in a sentinel hashtable. A begin
/// validation failure, or a process Stop-Function+return on an earlier record, sets it; the C# then
/// skips the remaining hops exactly as the single function scope would have short-circuited.
///
/// The begin block also lowers the confirm preference under -Force; in the source that setting is
/// shared with the process block through the one function scope. Across hops the process scope is
/// separate, so it is re-established at the top of the process hop, and the ShouldProcess gate selects
/// $PSCmdlet (whose confirm preference is lowered) under -Force and the real cmdlet otherwise - a bound
/// -Confirm cannot be overridden on the real cmdlet's own runtime.
///
/// The five notification levels (EventLog, Email, Netsend, Page, Delete) are normalized string-to-int
/// in begin and read in process, so they are carried across. NetsendLevel is a source variable that is
/// used in the body but was never declared as a parameter (only its ValidateSet attribute remains, the
/// declaration line is absent), so it is always $null and normalizes to 0; that is reproduced
/// faithfully - it is not a parameter here either.
///
/// Process output streams as it is produced. A single record can create jobs across several instances,
/// and each created job is emitted before a later instance may fail under -EnableException; buffering
/// them and losing them to a later terminating failure would hide jobs that were actually created.
///
/// This cmdlet supplies the real ShouldProcess runtime to the process hop. Surface pinned by
/// migration/baselines/New-DbaAgentJob.json.
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaAgentJob", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaAgentJobCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name of the job to create.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [ValidateNotNullOrEmpty]
    [PsStringCast]
    public string Job { get; set; } = null!;

    /// <summary>One or more schedules to attach to the job.</summary>
    [Parameter(Position = 3)]
    public object[]? Schedule { get; set; }

    /// <summary>One or more schedule ids to attach to the job.</summary>
    [Parameter(Position = 4)]
    public int[]? ScheduleId { get; set; }

    /// <summary>Create the job in a disabled state.</summary>
    [Parameter]
    public SwitchParameter Disabled { get; set; }

    /// <summary>The description for the job.</summary>
    [Parameter(Position = 5)]
    public string? Description { get; set; }

    /// <summary>The step id the job starts execution from.</summary>
    [Parameter(Position = 6)]
    public int StartStepId { get; set; }

    /// <summary>The category the job belongs to.</summary>
    [Parameter(Position = 7)]
    public string? Category { get; set; }

    /// <summary>The login used as the owner of the job.</summary>
    [Parameter(Position = 8)]
    public string? OwnerLogin { get; set; }

    /// <summary>When the job writes to the Windows event log.</summary>
    [Parameter(Position = 9)]
    [ValidateSet("0", "Never", "1", "OnSuccess", "2", "OnFailure", "3", "Always")]
    public object? EventLogLevel { get; set; }

    /// <summary>When the job notifies the e-mail operator.</summary>
    [Parameter(Position = 10)]
    [ValidateSet("0", "Never", "1", "OnSuccess", "2", "OnFailure", "3", "Always")]
    public object? EmailLevel { get; set; }

    /// <summary>When the job notifies the page operator.</summary>
    [Parameter(Position = 11)]
    [ValidateSet("0", "Never", "1", "OnSuccess", "2", "OnFailure", "3", "Always")]
    public object? PageLevel { get; set; }

    /// <summary>The operator notified by e-mail.</summary>
    [Parameter(Position = 12)]
    public string? EmailOperator { get; set; }

    /// <summary>The operator notified by net send.</summary>
    [Parameter(Position = 13)]
    public string? NetsendOperator { get; set; }

    /// <summary>The operator notified by pager.</summary>
    [Parameter(Position = 14)]
    public string? PageOperator { get; set; }

    /// <summary>When the job deletes itself after completion.</summary>
    [Parameter(Position = 15)]
    [ValidateSet("0", "Never", "1", "OnSuccess", "2", "OnFailure", "3", "Always")]
    public object? DeleteLevel { get; set; }

    /// <summary>Overwrite an existing job and create a missing category.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Begin-block results carried to the process hop: the five notification levels normalized from
    // their string/int forms to the SMO integer values. NetsendLevel is carried too even though it is
    // never a parameter (see the class remarks) - begin computes it to 0 and process reads it.
    private object? _eventLogLevel;
    private object? _emailLevel;
    private object? _netsendLevel;
    private object? _pageLevel;
    private object? _deleteLevel;
    // The function-scope interrupt: set by a direct begin Stop-Function (an operator-requirement gate),
    // or by a process Stop-Function+return on an earlier record. Either halts the remaining hops.
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            SqlInstance, EventLogLevel, EmailLevel, PageLevel, DeleteLevel,
            EmailOperator, NetsendOperator, PageOperator, Force.ToBool(), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaAgentJobBegin"))
            {
                if (sentinel["__newDbaAgentJobBegin"] is Hashtable state)
                {
                    _eventLogLevel = state["EventLogLevel"];
                    _emailLevel = state["EmailLevel"];
                    _netsendLevel = state["NetsendLevel"];
                    _pageLevel = state["PageLevel"];
                    _deleteLevel = state["DeleteLevel"];
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
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaAgentJobProcess"))
            {
                if (sentinel["__newDbaAgentJobProcess"] is Hashtable state)
                {
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
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
            SqlInstance, SqlCredential, Job, Schedule, ScheduleId, Disabled.ToBool(),
            Description, StartStepId, Category, OwnerLogin,
            _eventLogLevel, _emailLevel, _netsendLevel, _pageLevel, _deleteLevel,
            EmailOperator, NetsendOperator, PageOperator, Force.ToBool(), EnableException.ToBool(), this,
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

    // PS: the begin block. The five level normalizations and the three operator-requirement gates run
    // dot-sourced so a gate's "+ return" exits only the block, then the interrupt flag is read at
    // Get-Variable -Scope 0 and reported with the normalized levels. Edit: -FunctionName New-DbaAgentJob
    // on the direct Stop-Function sites. NetsendLevel is undeclared here exactly as in the source, so it
    // stays $null and normalizes to 0.
    private const string BeginScript = """
param($SqlInstance, $EventLogLevel, $EmailLevel, $PageLevel, $DeleteLevel, $EmailOperator, $NetsendOperator, $PageOperator, $Force, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $EventLogLevel, $EmailLevel, $PageLevel, $DeleteLevel, [string]$EmailOperator, [string]$NetsendOperator, [string]$PageOperator, $Force, $EnableException)

    . {
        if ($Force) { $ConfirmPreference = 'none' }

        # Check of the event log level is of type string and set the integer value
        if ($EventLogLevel -notin 1, 2, 3) {
            $EventLogLevel = switch ($EventLogLevel) {
                "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 }
                default { 0 }
            }
        }

        # Check of the email level is of type string and set the integer value
        if ($EmailLevel -notin 1, 2, 3) {
            $EmailLevel = switch ($EmailLevel) {
                "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 }
                default { 0 }
            }
        }

        # Check of the net send level is of type string and set the integer value
        if ($NetsendLevel -notin 1, 2, 3) {
            $NetsendLevel = switch ($NetsendLevel) {
                "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 }
                default { 0 }
            }
        }

        # Check of the page level is of type string and set the integer value
        if ($PageLevel -notin 1, 2, 3) {
            $PageLevel = switch ($PageLevel) {
                "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 }
                default { 0 }
            }
        }

        # Check of the delete level is of type string and set the integer value
        if ($DeleteLevel -notin 1, 2, 3) {
            $DeleteLevel = switch ($DeleteLevel) {
                "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 }
                default { 0 }
            }
        }

        # Check the e-mail operator name
        if (($EmailLevel -ge 1) -and (-not $EmailOperator)) {
            Stop-Function -Message "Please set the e-mail operator when the e-mail level parameter is set." -Target $SqlInstance -FunctionName New-DbaAgentJob
            return
        }

        # Check the e-mail operator name
        if (($NetsendLevel -ge 1) -and (-not $NetsendOperator)) {
            Stop-Function -Message "Please set the netsend operator when the netsend level parameter is set." -Target $SqlInstance -FunctionName New-DbaAgentJob
            return
        }

        # Check the e-mail operator name
        if (($PageLevel -ge 1) -and (-not $PageOperator)) {
            Stop-Function -Message "Please set the page operator when the page level parameter is set." -Target $SqlInstance -FunctionName New-DbaAgentJob
            return
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __newDbaAgentJobBegin = @{ EventLogLevel = $EventLogLevel; EmailLevel = $EmailLevel; NetsendLevel = $NetsendLevel; PageLevel = $PageLevel; DeleteLevel = $DeleteLevel; Interrupted = [bool]($__iv -and $__iv.Value) } }
} $SqlInstance $EventLogLevel $EmailLevel $PageLevel $DeleteLevel $EmailOperator $NetsendOperator $PageOperator $Force $EnableException @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM, dot-sourced so an early "+ return" (the missing-category gate)
    // exits only the block and the interrupt sentinel is still reported. Edits: $PSCmdlet.ShouldProcess
    // -> $__gate.ShouldProcess (the gate selector re-establishes the begin's -Force confirm lowering in
    // this separate scope), and -FunctionName New-DbaAgentJob on the direct Stop-Function/Write-Message
    // sites. The five levels are the carried begin results.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Job, $Schedule, $ScheduleId, $Disabled, $Description, $StartStepId, $Category, $OwnerLogin, $EventLogLevel, $EmailLevel, $NetsendLevel, $PageLevel, $DeleteLevel, $EmailOperator, $NetsendOperator, $PageOperator, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string]$Job, [object[]]$Schedule, [int[]]$ScheduleId, $Disabled, [string]$Description, [int]$StartStepId, [string]$Category, [string]$OwnerLogin, $EventLogLevel, $EmailLevel, $NetsendLevel, $PageLevel, $DeleteLevel, [string]$EmailOperator, [string]$NetsendOperator, [string]$PageOperator, $Force, $EnableException, $__realCmdlet)

    if ($Force) { $ConfirmPreference = 'none' }
    $__gate = if ($Force) { $PSCmdlet } else { $__realCmdlet }

    . {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaAgentJob
            }

            # Check if the job already exists
            if (-not $Force -and ($server.JobServer.Jobs.Name -contains $Job)) {
                Stop-Function -Message "Job $Job already exists on $instance" -Target $instance -Continue -FunctionName New-DbaAgentJob
            } elseif ($Force -and ($server.JobServer.Jobs.Name -contains $Job)) {
                Write-Message -Message "Job $Job already exists on $instance. Removing.." -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"

                if ($__gate.ShouldProcess($instance, "Removing the job $Job on $instance")) {
                    try {
                        $null = Remove-DbaAgentJob -SqlInstance $server -Job $Job -EnableException -Confirm:$false
                        $server.JobServer.Refresh()
                    } catch {
                        Stop-Function -Message "Couldn't remove job $Job from $instance" -Target $instance -Continue -ErrorRecord $_ -FunctionName New-DbaAgentJob
                    }
                }

            }

            if ($__gate.ShouldProcess($instance, "Creating the job on $instance")) {
                # Create the job object
                try {
                    $currentjob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job($server.JobServer, $Job)
                } catch {
                    if ($_.Exception.Message -match "newParent") {
                        Stop-Function -Message "Cannot create agent job through a contained availability group listener. SQL Server Agent objects are instance-level and must be managed on the instance directly. Please connect to the primary replica instead of the listener. Use Get-DbaAvailabilityGroup to find the current primary replica." -ErrorRecord $_ -Target $Job -Continue -FunctionName New-DbaAgentJob
                    } else {
                        Stop-Function -Message "Something went wrong creating the job." -Target $Job -Continue -ErrorRecord $_ -FunctionName New-DbaAgentJob
                    }
                }

                #region job options
                # Settings the options for the job
                if ($Disabled) {
                    Write-Message -Message "Setting job to disabled" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                    $currentjob.IsEnabled = $false
                } else {
                    Write-Message -Message "Setting job to enabled" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                    $currentjob.IsEnabled = $true
                }

                if ($Description.Length -ge 1) {
                    Write-Message -Message "Setting job description" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                    $currentjob.Description = $Description
                }

                if ($StartStepId -ge 1) {
                    Write-Message -Message "Setting job start step id" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                    $currentjob.StartStepID = $StartStepId
                }

                if ($Category.Length -ge 1) {
                    # Check if the job category exists
                    if ($Category -notin $server.JobServer.JobCategories.Name) {
                        if ($Force) {
                            if ($__gate.ShouldProcess($instance, "Creating job category on $instance")) {
                                try {
                                    # Create the category
                                    $server.JobServer.Refresh()
                                    New-DbaAgentJobCategory -SqlInstance $server -Category $Category
                                } catch {
                                    Stop-Function -Message "Couldn't create job category $Category from $instance" -Target $instance -Continue -ErrorRecord $_ -FunctionName New-DbaAgentJob
                                }
                            }
                        } else {
                            Stop-Function -Message "Job category $Category doesn't exist on $instance. Use -Force to create it." -Target $instance -FunctionName New-DbaAgentJob
                            return
                        }
                    } else {
                        Write-Message -Message "Setting job category" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                        $currentjob.Category = $Category
                    }
                }

                if ($OwnerLogin.Length -ge 1) {
                    # Check if the login name is present on the instance
                    if ($server.Logins.Name -contains $OwnerLogin) {
                        Write-Message -Message "Setting job owner login name to $OwnerLogin" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                        $currentjob.OwnerLoginName = $OwnerLogin
                    } else {
                        Stop-Function -Message "The owner $OwnerLogin does not exist on instance $instance" -Target $Job -Continue -FunctionName New-DbaAgentJob
                    }
                }

                if ($EventLogLevel -ge 0) {
                    Write-Message -Message "Setting job event log level" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                    $currentjob.EventLogLevel = $EventLogLevel
                }

                if ($EmailOperator) {
                    if ($EmailLevel -ge 1) {
                        # Check if the operator name is present
                        if ($server.JobServer.Operators.Name -contains $EmailOperator) {
                            Write-Message -Message "Setting job e-mail level" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                            $currentjob.EmailLevel = $EmailLevel

                            Write-Message -Message "Setting job e-mail operator" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                            $currentjob.OperatorToEmail = $EmailOperator
                        } else {
                            Stop-Function -Message "The e-mail operator name $EmailOperator does not exist on instance $instance. Exiting.." -Target $Job -Continue -FunctionName New-DbaAgentJob
                        }
                    } else {
                        Stop-Function -Message "Invalid combination of e-mail operator name $EmailOperator and email level $EmailLevel. Not setting the notification." -Target $Job -Continue -FunctionName New-DbaAgentJob
                    }
                }

                if ($NetsendOperator) {
                    if ($NetsendLevel -ge 1) {
                        # Check if the operator name is present
                        if ($server.JobServer.Operators.Name -contains $NetsendOperator) {
                            Write-Message -Message "Setting job netsend level" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                            $currentjob.NetSendLevel = $NetsendLevel

                            Write-Message -Message "Setting job netsend operator" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                            $currentjob.OperatorToNetSend = $NetsendOperator
                        } else {
                            Stop-Function -Message "The netsend operator name $NetsendOperator does not exist on instance $instance. Exiting.." -Target $Job -Continue -FunctionName New-DbaAgentJob
                        }
                    } else {
                        Write-Message -Message "Invalid combination of netsend operator name $NetsendOperator and netsend level $NetsendLevel. Not setting the notification." -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                    }
                }

                if ($PageOperator) {
                    if ($PageLevel -ge 1) {
                        # Check if the operator name is present
                        if ($server.JobServer.Operators.Name -contains $PageOperator) {
                            Write-Message -Message "Setting job pager level" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                            $currentjob.PageLevel = $PageLevel

                            Write-Message -Message "Setting job pager operator" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                            $currentjob.OperatorToPage = $PageOperator
                        } else {
                            Stop-Function -Message "The page operator name $PageOperator does not exist on instance $instance. Exiting.." -Target $Job -Continue -FunctionName New-DbaAgentJob
                        }
                    } else {
                        Write-Message -Message "Invalid combination of page operator name $PageOperator and page level $PageLevel. Not setting the notification." -Level Warning -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                    }
                }

                if ($DeleteLevel -ge 0) {
                    Write-Message -Message "Setting job delete level" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                    $currentjob.DeleteLevel = $DeleteLevel
                }
                #endregion job options

                try {
                    Write-Message -Message "Creating the job" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"

                    # Create the job
                    $currentjob.Create()

                    Write-Message -Message "Job created with UID $($currentjob.JobID)" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"

                    # Make sure the target is set for the job
                    Write-Message -Message "Applying the target (local) to job $Job" -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"
                    $currentjob.ApplyToTargetServer("(local)")

                    # Refresh the SMO - another bug in SMO? As this should not be needed...
                    $currentjob.Refresh()

                    # If a schedule needs to be attached
                    if ($Schedule) {
                        $null = Set-DbaAgentJob -SqlInstance $server -Job $currentjob -Schedule $Schedule
                    }

                    if ($ScheduleId) {
                        $null = Set-DbaAgentJob -SqlInstance $server -Job $currentjob -ScheduleId $ScheduleId
                    }
                } catch {
                    Stop-Function -Message "Something went wrong creating the job" -Target $currentjob -ErrorRecord $_ -Continue -FunctionName New-DbaAgentJob
                }
            }

            Add-TeppCacheItem -SqlInstance $server -Type job -Name $Job

            Get-DbaAgentJob -SqlInstance $server -Job $Job
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __newDbaAgentJobProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $SqlInstance $SqlCredential $Job $Schedule $ScheduleId $Disabled $Description $StartStepId $Category $OwnerLogin $EventLogLevel $EmailLevel $NetsendLevel $PageLevel $DeleteLevel $EmailOperator $NetsendOperator $PageOperator $Force $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";

    // PS: the end block. It only runs when neither begin nor an earlier process record set the
    // interrupt (the C# guards that), so the Test-FunctionInterrupt check is preserved for fidelity but
    // never fires here. Edit: -FunctionName New-DbaAgentJob on the direct Write-Message. EnableException
    // is marshaled through because it is in scope in the source's end block (the whole function shares
    // one scope); the body does not read it, but carrying it keeps the hop a well-formed positional pass.
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
    Write-Message -Message "Finished creating job(s)." -Level Verbose -FunctionName New-DbaAgentJob -ModuleName "dbatools"
} $EnableException @__commonParameters 3>&1 2>&1
""";
}

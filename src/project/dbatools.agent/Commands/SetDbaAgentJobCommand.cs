#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoJob = Microsoft.SqlServer.Management.Smo.Agent.Job;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Modifies properties of one or more existing SQL Server Agent jobs.
/// </summary>
/// <remarks>
/// The notification-level normalization, the operator/level validation, the instance connection, the
/// job resolution, the property assignments, the Alter, and the output all run the original dbatools
/// PowerShell body VERBATIM inside the dbatools module scope rather than being reimplemented in C#, so
/// the engine decides the observable details.
///
/// begin/process/end. The begin block normalizes EventLogLevel/EmailLevel/NetsendLevel/PageLevel/
/// DeleteLevel from strings to ints and runs operator/level cross-validation whose no-Continue
/// Stop-Functions set the function-scope interrupt and return. The five normalized levels are read by
/// the process block, so they are captured once from the begin sentinel and threaded into every
/// record. Under -EnableException the begin Stop-Functions throw instead.
///
/// INTERRUPT is carried TWO ways. begin -> process: the begin validations' interrupt is reported in
/// the begin sentinel. process -> process (CROSS-RECORD): unlike the sibling schedule commands, the
/// PROCESS block ALSO contains no-Continue Stop-Functions (the InputObject/Job guard, "job doesn't
/// exist", the category force-create catch, and "category doesn't exist use -Force") that set the
/// function-scope interrupt, and the process block's own "if (Test-FunctionInterrupt) { return }"
/// reads it. In the source that interrupt persists across piped InputObject records; here each process
/// record emits an interrupt sentinel (Get-Variable -Scope 0 after a dot-sourced body) and the C#
/// OR-accumulates it into _interrupted, so ProcessRecord's guard short-circuits every later record
/// once any begin OR process validation has fired. The source's own Test-FunctionInterrupt line is
/// kept verbatim but is inert at record entry (the C# guard already short-circuited an interrupted
/// pipeline, and the interrupt is only set later within the same record).
///
/// The end block has NO Test-FunctionInterrupt, so EndProcessing runs the end hop UNCONDITIONALLY.
///
/// $InputObject is NOT carried across records: it is ValueFromPipeline (rebound each record) and only
/// appended within a record; the appends do not persist across records in the source. No other process
/// variable leaks across records.
///
/// The begin block's "if (\$Force) { \$ConfirmPreference = 'none' }" is folded to the top of the
/// process hop with \$__gate = if (\$Force) { \$PSCmdlet } else { \$__realCmdlet }; all five
/// ShouldProcess sites use \$__gate. The five Test-Bound sites become \$__bound.ContainsKey lookups on
/// this cmdlet's own bound parameters.
///
/// Output streams: each altered job is emitted before a later one may fail under -EnableException
/// (DEF-001), so the process hop uses InvokeScopedStreaming. This cmdlet supplies the real
/// ShouldProcess runtime (ConfirmImpact Low). Surface pinned by migration/baselines/Set-DbaAgentJob.json.
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaAgentJob", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class SetDbaAgentJobCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name of the job(s) to modify.</summary>
    [Parameter(Position = 2)]
    public object[]? Job { get; set; }

    /// <summary>The schedule(s) to attach to the job.</summary>
    [Parameter(Position = 3)]
    public object[]? Schedule { get; set; }

    /// <summary>The schedule id(s) to attach to the job.</summary>
    [Parameter(Position = 4)]
    public int[]? ScheduleId { get; set; }

    /// <summary>A new name for the job.</summary>
    [Parameter(Position = 5)]
    public string? NewName { get; set; }

    /// <summary>Enable the job.</summary>
    [Parameter]
    public SwitchParameter Enabled { get; set; }

    /// <summary>Disable the job.</summary>
    [Parameter]
    public SwitchParameter Disabled { get; set; }

    /// <summary>The description for the job.</summary>
    [Parameter(Position = 6)]
    public string? Description { get; set; }

    /// <summary>The start step id for the job.</summary>
    [Parameter(Position = 7)]
    public int StartStepId { get; set; }

    /// <summary>The category for the job.</summary>
    [Parameter(Position = 8)]
    public string? Category { get; set; }

    /// <summary>The owner login for the job.</summary>
    [Parameter(Position = 9)]
    public string? OwnerLogin { get; set; }

    /// <summary>The event log level for the job.</summary>
    [Parameter(Position = 10)]
    [ValidateSet("0", "Never", "1", "OnSuccess", "2", "OnFailure", "3", "Always")]
    public object? EventLogLevel { get; set; }

    /// <summary>The e-mail notification level for the job.</summary>
    [Parameter(Position = 11)]
    [ValidateSet("0", "Never", "1", "OnSuccess", "2", "OnFailure", "3", "Always")]
    public object? EmailLevel { get; set; }

    /// <summary>The net send notification level for the job.</summary>
    [Parameter(Position = 12)]
    [ValidateSet("0", "Never", "1", "OnSuccess", "2", "OnFailure", "3", "Always")]
    public object? NetsendLevel { get; set; }

    /// <summary>The pager notification level for the job.</summary>
    [Parameter(Position = 13)]
    [ValidateSet("0", "Never", "1", "OnSuccess", "2", "OnFailure", "3", "Always")]
    public object? PageLevel { get; set; }

    /// <summary>The e-mail operator for the job.</summary>
    [Parameter(Position = 14)]
    public string? EmailOperator { get; set; }

    /// <summary>The net send operator for the job.</summary>
    [Parameter(Position = 15)]
    public string? NetsendOperator { get; set; }

    /// <summary>The pager operator for the job.</summary>
    [Parameter(Position = 16)]
    public string? PageOperator { get; set; }

    /// <summary>The delete level for the job.</summary>
    [Parameter(Position = 17)]
    [ValidateSet("0", "Never", "1", "OnSuccess", "2", "OnFailure", "3", "Always")]
    public object? DeleteLevel { get; set; }

    /// <summary>Create the job category if it does not exist.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>SMO Agent Job objects piped in.</summary>
    [Parameter(Position = 18, ValueFromPipeline = true)]
    public SmoJob[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which
    // the inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    // The function-scope interrupt. Set by the begin validations (carried via the begin sentinel) AND
    // by the process validations (carried record-to-record via the process sentinel); ProcessRecord
    // guards on it. The end block does NOT check it, so EndProcessing runs unconditionally.
    private bool _interrupted;

    // begin-normalized notification levels the process block reads (one-shot, pure functions of the
    // non-pipeline parameters).
    private object? _eventLogLevel;
    private object? _emailLevel;
    private object? _netsendLevel;
    private object? _pageLevel;
    private object? _deleteLevel;

    protected override void BeginProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            SqlInstance, EventLogLevel, EmailLevel, NetsendLevel, PageLevel, DeleteLevel,
            EmailOperator, NetsendOperator, PageOperator, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__setDbaAgentJobBegin"))
            {
                if (sentinel["__setDbaAgentJobBegin"] is Hashtable state)
                {
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                    _eventLogLevel = state["EventLogLevel"];
                    _emailLevel = state["EmailLevel"];
                    _netsendLevel = state["NetsendLevel"];
                    _pageLevel = state["PageLevel"];
                    _deleteLevel = state["DeleteLevel"];
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
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__setDbaAgentJobProcess"))
            {
                if (sentinel["__setDbaAgentJobProcess"] is Hashtable state)
                {
                    _interrupted = _interrupted || LanguagePrimitives.IsTrue(state["Interrupted"]);
                }
                return;
            }
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
            SqlInstance, SqlCredential, Job, InputObject, NewName, Schedule, ScheduleId, Enabled.ToBool(),
            Disabled.ToBool(), Description, Category, StartStepId, OwnerLogin, EmailOperator,
            NetsendOperator, PageOperator, _eventLogLevel, _emailLevel, _netsendLevel, _pageLevel,
            _deleteLevel, Force.ToBool(), EnableException.ToBool(), new Hashtable(MyInvocation.BoundParameters),
            this, NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
    {
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

    // PS: the begin block VERBATIM apart from -FunctionName Set-DbaAgentJob on the direct Stop-Function
    // sites. The "if (\$Force) { \$ConfirmPreference = 'none' }" line is folded into the process hop.
    // Dot-sourced so the validation returns still emit the sentinel, which carries both the interrupt
    // flag and the five normalized notification levels the process block reads.
    private const string BeginScript = """
param($SqlInstance, $EventLogLevel, $EmailLevel, $NetsendLevel, $PageLevel, $DeleteLevel, $EmailOperator, $NetsendOperator, $PageOperator, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [object]$EventLogLevel, [object]$EmailLevel, [object]$NetsendLevel, [object]$PageLevel, [object]$DeleteLevel, [string]$EmailOperator, [string]$NetsendOperator, [string]$PageOperator, $EnableException)
    . {
        # Check of the event log level is of type string and set the integer value
        if (($EventLogLevel -notin 0, 1, 2, 3) -and ($null -ne $EventLogLevel)) {
            $EventLogLevel = switch ($EventLogLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check of the email level is of type string and set the integer value
        if (($EmailLevel -notin 0, 1, 2, 3) -and ($null -ne $EmailLevel)) {
            $EmailLevel = switch ($EmailLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check of the net send level is of type string and set the integer value
        if (($NetsendLevel -notin 0, 1, 2, 3) -and ($null -ne $NetsendLevel)) {
            $NetsendLevel = switch ($NetsendLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check of the page level is of type string and set the integer value
        if (($PageLevel -notin 0, 1, 2, 3) -and ($null -ne $PageLevel)) {
            $PageLevel = switch ($PageLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check of the delete level is of type string and set the integer value
        if (($DeleteLevel -notin 0, 1, 2, 3) -and ($null -ne $DeleteLevel)) {
            $DeleteLevel = switch ($DeleteLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check the e-mail operator name
        if (($EmailLevel -ge 1) -and (-not $EmailOperator)) {
            Stop-Function -Message "Please set the e-mail operator when the e-mail level parameter is set." -Target $SqlInstance -FunctionName Set-DbaAgentJob
            return
        }

        # Check the e-mail level parameter
        if ($EmailOperator -and ($null -eq $EmailLevel)) {
            Stop-Function -Message "Please set the e-mail level parameter when the e-mail level operator is set." -Target $SqlInstance -FunctionName Set-DbaAgentJob
            return
        }

        # Check the net send operator name
        if (($NetsendLevel -ge 1) -and (-not $NetsendOperator)) {
            Stop-Function -Message "Please set the netsend operator when the netsend level parameter is set." -Target $SqlInstance -FunctionName Set-DbaAgentJob
            return
        }

        # Check the net send level parameter
        if ($NetsendOperator -and ($null -eq $NetsendLevel)) {
            Stop-Function -Message "Please set the net send level parameter when the net send level operator is set." -Target $SqlInstance -FunctionName Set-DbaAgentJob
            return
        }

        # Check the page operator name
        if (($PageLevel -ge 1) -and (-not $PageOperator)) {
            Stop-Function -Message "Please set the page operator when the page level parameter is set." -Target $SqlInstance -FunctionName Set-DbaAgentJob
            return
        }

        # Check the page level parameter
        if ($PageOperator -and ($null -eq $PageLevel)) {
            Stop-Function -Message "Please set the page level parameter when the page level operator is set." -Target $SqlInstance -FunctionName Set-DbaAgentJob
            return
        }
    }
    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __setDbaAgentJobBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value); EventLogLevel = $EventLogLevel; EmailLevel = $EmailLevel; NetsendLevel = $NetsendLevel; PageLevel = $PageLevel; DeleteLevel = $DeleteLevel } }
} $SqlInstance $EventLogLevel $EmailLevel $NetsendLevel $PageLevel $DeleteLevel $EmailOperator $NetsendOperator $PageOperator $EnableException @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM apart from $PSCmdlet.ShouldProcess -> $__gate.ShouldProcess, the
    // five Test-Bound sites -> $__bound.ContainsKey, and -FunctionName Set-DbaAgentJob on the direct
    // Stop-Function/Write-Message sites. The begin Force/ConfirmPreference line + gate selection are
    // prepended (USER -Force). The body is dot-sourced so the no-Continue validation returns still reach
    // the interrupt sentinel, which carries the process-set interrupt to the next record.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Job, $InputObject, $NewName, $Schedule, $ScheduleId, $Enabled, $Disabled, $Description, $Category, $StartStepId, $OwnerLogin, $EmailOperator, $NetsendOperator, $PageOperator, $EventLogLevel, $EmailLevel, $NetsendLevel, $PageLevel, $DeleteLevel, $Force, $EnableException, $__bound, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Job, [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject, [string]$NewName, [object[]]$Schedule, [int[]]$ScheduleId, $Enabled, $Disabled, [string]$Description, [string]$Category, [int]$StartStepId, [string]$OwnerLogin, [string]$EmailOperator, [string]$NetsendOperator, [string]$PageOperator, $EventLogLevel, $EmailLevel, $NetsendLevel, $PageLevel, $DeleteLevel, $Force, $EnableException, $__bound, $__realCmdlet)
    if ($Force) { $ConfirmPreference = 'none' }
    $__gate = if ($Force) { $PSCmdlet } else { $__realCmdlet }
    . {

        if (Test-FunctionInterrupt) { return }

        if ((-not $InputObject) -and (-not $Job)) {
            Stop-Function -Message "You must specify a job name or pipe in results from another command" -Target $SqlInstance -FunctionName Set-DbaAgentJob
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaAgentJob
            }

            foreach ($j in $Job) {

                # Check if the job exists
                if ($server.JobServer.Jobs.Name -notcontains $j) {
                    Stop-Function -Message "Job $j doesn't exists on $instance" -Target $instance -FunctionName Set-DbaAgentJob
                } else {
                    # Get the job
                    try {
                        $InputObject += $server.JobServer.Jobs[$j]

                        # Refresh the object
                        $InputObject.Refresh()
                    } catch {
                        Stop-Function -Message "Something went wrong retrieving the job" -Target $j -ErrorRecord $_ -Continue -FunctionName Set-DbaAgentJob
                    }
                }
            }
        }

        foreach ($currentjob in $InputObject) {
            $server = $currentjob.Parent.Parent

            #region job options
            # Settings the options for the job
            if ($NewName) {
                if ($__gate.ShouldProcess($server, "Setting job name of $($currentjob.Name) to $NewName")) {
                    $currentjob.Rename($NewName)
                }
            }

            if ($Schedule) {
                # Loop through each of the schedules
                foreach ($s in $Schedule) {
                    if ($server.JobServer.SharedSchedules.Name -contains $s) {
                        # Get the schedule ID
                        $sID = $server.JobServer.SharedSchedules[$s].ID

                        # Add schedule to job
                        if ($__gate.ShouldProcess($server, "Adding schedule id $sID to job $($currentjob.Name)")) {
                            $currentjob.AddSharedSchedule($sID)
                        }
                    } else {
                        Stop-Function -Message "Schedule $s cannot be found on instance $instance" -Target $s -Continue -FunctionName Set-DbaAgentJob
                    }

                }
            }

            if ($ScheduleId) {
                # Loop through each of the schedules IDs
                foreach ($sID in $ScheduleId) {
                    # Check if the schedule is
                    if ($server.JobServer.SharedSchedules.ID -contains $sID) {
                        # Add schedule to job
                        if ($__gate.ShouldProcess($server, "Adding schedule id $sID to job $($currentjob.Name)")) {
                            $currentjob.AddSharedSchedule($sID)
                        }
                    } else {
                        Stop-Function -Message "Schedule ID $sID cannot be found on instance $instance" -Target $sID -Continue -FunctionName Set-DbaAgentJob
                    }
                }
            }

            if ($Enabled) {
                Write-Message -Message "Setting job to enabled" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
                $currentjob.IsEnabled = $true
            }

            if ($Disabled) {
                Write-Message -Message "Setting job to disabled" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
                $currentjob.IsEnabled = $false
            }

            if ($Description) {
                Write-Message -Message "Setting job description to $Description" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
                $currentjob.Description = $Description
            }

            if ($Category) {
                # Check if the job category exists
                if ($Category -notin $server.JobServer.JobCategories.Name) {
                    if ($Force) {
                        if ($__gate.ShouldProcess($instance, "Creating job category on $instance")) {
                            try {
                                # Create the category
                                New-DbaAgentJobCategory -SqlInstance $server -Category $Category

                                Write-Message -Message "Setting job category to $Category" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
                                $currentjob.Category = $Category
                            } catch {
                                Stop-Function -Message "Couldn't create job category $Category from $instance" -Target $instance -ErrorRecord $_ -FunctionName Set-DbaAgentJob
                            }
                        }
                    } else {
                        Stop-Function -Message "Job category $Category doesn't exist on $instance. Use -Force to create it." -Target $instance -FunctionName Set-DbaAgentJob
                        return
                    }
                } else {
                    Write-Message -Message "Setting job category to $Category" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
                    $currentjob.Category = $Category
                }
            }

            if ($StartStepId) {
                # Get the job steps
                $currentjobSteps = $currentjob.JobSteps

                # Check if there are any job steps
                if ($currentjobSteps.Count -ge 1) {
                    # Check if the start step id value is one of the job steps in the job
                    if ($currentjobSteps.ID -contains $StartStepId) {
                        Write-Message -Message "Setting job start step id to $StartStepId" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
                        $currentjob.StartStepID = $StartStepId
                    } else {
                        Write-Message -Message "The step id is not present in job $j on instance $instance" -Warning -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
                    }

                } else {
                    Stop-Function -Message "There are no job steps present for job $j on instance $instance" -Target $instance -Continue -FunctionName Set-DbaAgentJob
                }

            }

            if ($OwnerLogin) {
                # Check if the login name is present on the instance
                if ($server.Logins.Name -contains $OwnerLogin) {
                    Write-Message -Message "Setting job owner login name to $OwnerLogin" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
                    $currentjob.OwnerLoginName = $OwnerLogin
                } else {
                    Stop-Function -Message "The given owner log in name $OwnerLogin does not exist on instance $instance" -Target $instance -Continue -FunctionName Set-DbaAgentJob
                }
            }

            if ($__bound.ContainsKey('EventLogLevel')) {
                Write-Message -Message "Setting job event log level to $EventlogLevel" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
                $currentjob.EventLogLevel = $EventLogLevel
            }

            if ($__bound.ContainsKey('EmailLevel')) {
                # Check if the notifiction needs to be removed
                if ($EmailLevel -eq 0) {
                    # Remove the operator
                    $currentjob.OperatorToEmail = $null

                    # Remove the notification
                    $currentjob.EmailLevel = $EmailLevel
                } else {
                    # Check if either the operator e-mail parameter is set or the operator is set in the job
                    if ($EmailOperator -or $currentjob.OperatorToEmail) {
                        Write-Message -Message "Setting job e-mail level to $EmailLevel" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
                        $currentjob.EmailLevel = $EmailLevel
                    } else {
                        Stop-Function -Message "Cannot set e-mail level $EmailLevel without a valid e-mail operator name" -Target $instance -Continue -FunctionName Set-DbaAgentJob
                    }
                }
            }

            if ($__bound.ContainsKey('NetsendLevel')) {
                # Check if the notifiction needs to be removed
                if ($NetsendLevel -eq 0) {
                    # Remove the operator
                    $currentjob.OperatorToNetSend = $null

                    # Remove the notification
                    $currentjob.NetSendLevel = $NetsendLevel
                } else {
                    # Check if either the operator netsend parameter is set or the operator is set in the job
                    if ($NetsendOperator -or $currentjob.OperatorToNetSend) {
                        Write-Message -Message "Setting job netsend level to $NetsendLevel" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
                        $currentjob.NetSendLevel = $NetsendLevel
                    } else {
                        Stop-Function -Message "Cannot set netsend level $NetsendLevel without a valid netsend operator name" -Target $instance -Continue -FunctionName Set-DbaAgentJob
                    }
                }
            }

            if ($__bound.ContainsKey('PageLevel')) {
                # Check if the notifiction needs to be removed
                if ($PageLevel -eq 0) {
                    # Remove the operator
                    $currentjob.OperatorToPage = $null

                    # Remove the notification
                    $currentjob.PageLevel = $PageLevel
                } else {
                    # Check if either the operator pager parameter is set or the operator is set in the job
                    if ($PageOperator -or $currentjob.OperatorToPage) {
                        Write-Message -Message "Setting job pager level to $PageLevel" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
                        $currentjob.PageLevel = $PageLevel
                    } else {
                        Stop-Function -Message "Cannot set page level $PageLevel without a valid netsend operator name" -Target $instance -Continue -FunctionName Set-DbaAgentJob
                    }
                }
            }

            # Check the current setting of the job's email level
            if ($EmailOperator) {
                # Check if the operator name is present
                if ($server.JobServer.Operators.Name -contains $EmailOperator) {
                    Write-Message -Message "Setting job e-mail operator to $EmailOperator" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
                    $currentjob.OperatorToEmail = $EmailOperator
                } else {
                    Stop-Function -Message "The e-mail operator name $EmailOperator does not exist on instance $instance. Exiting.." -Target $j -Continue -FunctionName Set-DbaAgentJob
                }
            }

            if ($NetsendOperator) {
                # Check if the operator name is present
                if ($server.JobServer.Operators.Name -contains $NetsendOperator) {
                    Write-Message -Message "Setting job netsend operator to $NetsendOperator" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
                    $currentjob.OperatorToNetSend = $NetsendOperator
                } else {
                    Stop-Function -Message "The netsend operator name $NetsendOperator does not exist on instance $instance. Exiting.." -Target $j -Continue -FunctionName Set-DbaAgentJob
                }
            }

            if ($PageOperator) {
                # Check if the operator name is present
                if ($server.JobServer.Operators.Name -contains $PageOperator) {
                    Write-Message -Message "Setting job pager operator to $PageOperator" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
                    $currentjob.OperatorToPage = $PageOperator
                } else {
                    Stop-Function -Message "The page operator name $PageOperator does not exist on instance $instance. Exiting.." -Target $instance -Continue -FunctionName Set-DbaAgentJob
                }
            }

            if ($__bound.ContainsKey('DeleteLevel')) {
                Write-Message -Message "Setting job delete level to $DeleteLevel" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
                $currentjob.DeleteLevel = $DeleteLevel
            }
            #endregion job options

            # Execute
            if ($__gate.ShouldProcess($SqlInstance, "Changing the job $j")) {
                try {
                    Write-Message -Message "Changing the job" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"

                    # Change the job
                    $currentjob.Alter()
                } catch {
                    Stop-Function -Message "Something went wrong changing the job" -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaAgentJob
                }

                # Refresh the SMO - another bug in SMO? As this should not be needed...
                $currentjob.Refresh()

                Get-DbaAgentJob -SqlInstance $server -Job $currentjob.Name
            }
        }
    }
    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __setDbaAgentJobProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $SqlInstance $SqlCredential $Job $InputObject $NewName $Schedule $ScheduleId $Enabled $Disabled $Description $Category $StartStepId $OwnerLogin $EmailOperator $NetsendOperator $PageOperator $EventLogLevel $EmailLevel $NetsendLevel $PageLevel $DeleteLevel $Force $EnableException $__bound $__realCmdlet @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM apart from -FunctionName Set-DbaAgentJob on the direct Write-Message.
    // The source end has NO Test-FunctionInterrupt, so EndProcessing runs this unconditionally.
    private const string EndScript = """
param($EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($EnableException)
    Write-Message -Message "Finished changing job(s)" -Level Verbose -FunctionName Set-DbaAgentJob -ModuleName "dbatools"
} $EnableException @__commonParameters 3>&1 2>&1
""";
}

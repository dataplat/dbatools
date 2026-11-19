#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Modifies properties of existing SQL Server Agent job schedules.
/// </summary>
/// <remarks>
/// The frequency/subday/relative-interval normalization, the date/time validation and formatting,
/// the instance connection, the job/schedule resolution, the property assignments, the Alter, and
/// the output all run the original dbatools PowerShell body inside the dbatools module scope rather
/// than being reimplemented in C#, so the engine decides the observable details.
///
/// The function has begin/process/end blocks. The begin block runs one-shot validations (daily
/// interval range, recurrence factor, subday interval, start/end date + time regex) whose
/// no-Continue Stop-Functions set the function-scope interrupt and return; both the process AND the
/// end blocks short-circuit via Test-FunctionInterrupt, so the interrupt is carried begin ->
/// (process, end) via the _interrupted field (the begin hop reads it with Get-Variable -Scope 0
/// after a dot-sourced body and reports it in a sentinel, and BOTH ProcessRecord and EndProcessing
/// guard on it). Under -EnableException the begin Stop-Functions throw instead, terminating before
/// any record.
///
/// The begin block ALSO computes values the process block reads: $FrequencyType, $FrequencySubdayType,
/// $FrequencyRelativeInterval and $FrequencyRecurrenceFactor are normalized to integers; $StartDate,
/// $EndDate, $StartTime, $EndTime are reformatted; and $Interval is derived from $FrequencyInterval.
/// These are one-shot (pure functions of the non-pipeline parameters) so they are captured once from
/// the begin sentinel and threaded into every process record. $Interval is special: the process body
/// mutates it (line "if (...FrequencyInterval -eq 0 -and $Interval -lt 1) { $Interval = 1 }") and in
/// the source that mutation persists across pipeline records via function scope, so it is carried
/// forward - seeded from begin, re-emitted by each process record in a sentinel, fed to the next.
/// The process body is dot-sourced so the inner "return" after the Alter catch still reaches that
/// sentinel emit.
///
/// The begin block's "if (\$Force) { \$ConfirmPreference = 'none' }" is folded into the top of the
/// process hop with \$__gate = if (\$Force) { \$PSCmdlet } else { \$__realCmdlet }; both ShouldProcess
/// sites route through \$__gate. There is no Test-Bound in this function.
///
/// Output streams: each altered schedule is emitted before a later one may fail under
/// -EnableException (DEF-001), so the process hop uses InvokeScopedStreaming. This cmdlet supplies the
/// real ShouldProcess runtime (ConfirmImpact Low). Surface pinned by
/// migration/baselines/Set-DbaAgentSchedule.json.
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaAgentSchedule", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class SetDbaAgentScheduleCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name of the job(s) that contain the schedule to modify.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 2)]
    [ValidateNotNullOrEmpty]
    public object[]? Job { get; set; }

    /// <summary>The name of the existing schedule to modify.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 3)]
    [ValidateNotNullOrEmpty]
    [Alias("ScheduleName")]
    [PsStringCast]
    public string? Schedule { get; set; }

    /// <summary>A new name for the schedule.</summary>
    [Parameter(Position = 4)]
    public string? NewName { get; set; }

    /// <summary>Enable the schedule.</summary>
    [Parameter]
    public SwitchParameter Enabled { get; set; }

    /// <summary>Disable the schedule.</summary>
    [Parameter]
    public SwitchParameter Disabled { get; set; }

    /// <summary>The overall frequency pattern for the schedule.</summary>
    [Parameter(Position = 5)]
    [ValidateSet("Once", "OneTime", "Daily", "Weekly", "Monthly", "MonthlyRelative", "AgentStart", "AutoStart", "IdleComputer", "OnIdle", "1", "4", "8", "16", "32", "64", "128")]
    public object? FrequencyType { get; set; }

    /// <summary>The days or intervals the job runs, based on FrequencyType.</summary>
    [Parameter(Position = 6)]
    public object[]? FrequencyInterval { get; set; }

    /// <summary>The unit of time for running jobs multiple times within a day.</summary>
    [Parameter(Position = 7)]
    [ValidateSet("1", "Once", "Time", "2", "Seconds", "Second", "4", "Minutes", "Minute", "8", "Hours", "Hour")]
    public object? FrequencySubdayType { get; set; }

    /// <summary>How many subday units to wait between executions.</summary>
    [Parameter(Position = 8)]
    public int FrequencySubdayInterval { get; set; }

    /// <summary>Which occurrence within the month for MonthlyRelative schedules.</summary>
    [Parameter(Position = 9)]
    [ValidateSet("Unused", "First", "Second", "Third", "Fourth", "Last")]
    public object? FrequencyRelativeInterval { get; set; }

    /// <summary>The interval between occurrences for weekly/monthly schedules.</summary>
    [Parameter(Position = 10)]
    public int FrequencyRecurrenceFactor { get; set; }

    /// <summary>The earliest date the schedule becomes active (yyyyMMdd).</summary>
    [Parameter(Position = 11)]
    public string? StartDate { get; set; }

    /// <summary>The last date the schedule is active (yyyyMMdd).</summary>
    [Parameter(Position = 12)]
    public string? EndDate { get; set; }

    /// <summary>The daily start time (HHMMSS).</summary>
    [Parameter(Position = 13)]
    public string? StartTime { get; set; }

    /// <summary>The daily end time (HHMMSS).</summary>
    [Parameter(Position = 14)]
    public string? EndTime { get; set; }

    /// <summary>Bypass some parameter validation errors by applying sensible defaults.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which
    // the inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    // The function-scope interrupt set by the begin validations; carried to guard both the process
    // records and the end block (both check Test-FunctionInterrupt in the source).
    private bool _interrupted;

    // begin-computed values the process block reads. All are one-shot (pure functions of the
    // non-pipeline parameters), captured once from the begin sentinel and threaded into every record.
    private object? _frequencyType;
    private object? _frequencySubdayType;
    private object? _frequencyRelativeInterval;
    private object? _frequencyRecurrenceFactor;
    private object? _startDate;
    private object? _endDate;
    private object? _startTime;
    private object? _endTime;

    // $Interval: seeded from begin, mutated by the process body, persisted across records (function
    // scope in the source) by re-emitting it from each process record's sentinel.
    private object? _interval;

    protected override void BeginProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            SqlInstance, Schedule, FrequencyType, FrequencyInterval, FrequencySubdayType,
            FrequencySubdayInterval, FrequencyRelativeInterval, FrequencyRecurrenceFactor,
            StartDate, EndDate, StartTime, EndTime, Force.ToBool(), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__setDbaAgentScheduleBegin"))
            {
                if (sentinel["__setDbaAgentScheduleBegin"] is Hashtable state)
                {
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                    _frequencyType = state["FrequencyType"];
                    _frequencySubdayType = state["FrequencySubdayType"];
                    _frequencyRelativeInterval = state["FrequencyRelativeInterval"];
                    _frequencyRecurrenceFactor = state["FrequencyRecurrenceFactor"];
                    _startDate = state["StartDate"];
                    _endDate = state["EndDate"];
                    _startTime = state["StartTime"];
                    _endTime = state["EndTime"];
                    _interval = state["Interval"];
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
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__setDbaAgentScheduleProcess"))
            {
                if (sentinel["__setDbaAgentScheduleProcess"] is Hashtable state)
                {
                    _interval = state["Interval"];
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
            SqlInstance, SqlCredential, Job, Schedule, NewName, Enabled.ToBool(), Disabled.ToBool(),
            FrequencySubdayInterval, _frequencyType, _interval, _frequencySubdayType,
            _frequencyRelativeInterval, _frequencyRecurrenceFactor, _startDate, _endDate, _startTime,
            _endTime, Force.ToBool(), EnableException.ToBool(), this,
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

    // PS: the begin block VERBATIM apart from -FunctionName Set-DbaAgentSchedule on the direct
    // Stop-Function/Write-Message sites. The "if (\$Force) { \$ConfirmPreference = 'none' }" line is
    // folded into the process hop. Dot-sourced so the validation returns still emit the sentinel, which
    // carries both the interrupt flag and the computed values the process block reads.
    private const string BeginScript = """
param($SqlInstance, $Schedule, $FrequencyType, $FrequencyInterval, $FrequencySubdayType, $FrequencySubdayInterval, $FrequencyRelativeInterval, $FrequencyRecurrenceFactor, $StartDate, $EndDate, $StartTime, $EndTime, $Force, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [string]$Schedule, [object]$FrequencyType, [object[]]$FrequencyInterval, [object]$FrequencySubdayType, [int]$FrequencySubdayInterval, [object]$FrequencyRelativeInterval, [int]$FrequencyRecurrenceFactor, [string]$StartDate, [string]$EndDate, [string]$StartTime, [string]$EndTime, $Force, $EnableException)
    . {
        # Check of the FrequencyType value is of type string and set the integer value
        if ($FrequencyType -notin 1, 4, 8, 16, 32, 64, 128) {
            [int]$FrequencyType =
            switch ($FrequencyType) {
                "Once" { 1 }
                "OneTime" { 1 }
                "Daily" { 4 }
                "Weekly" { 8 }
                "Monthly" { 16 }
                "MonthlyRelative" { 32 }
                "AgentStart" { 64 }
                "AutoStart" { 64 }
                "IdleComputer" { 128 }
                "OnIdle" { 128 }
                default { 1 }
            }
        }

        # Check of the FrequencySubdayType value is of type string and set the integer value
        if ($FrequencySubdayType -notin 0, 1, 2, 4, 8) {
            [int]$FrequencySubdayType =
            switch ($FrequencySubdayType) {
                "Once" { 1 }
                "Time" { 1 }
                "Seconds" { 2 }
                "Second" { 2 }
                "Minutes" { 4 }
                "Minute" { 4 }
                "Hours" { 8 }
                "Hour" { 8 }
                default { 0 }
            }
        }

        # Check if the interval for daily frequency is valid
        if (($FrequencyType -in 4) -and ($FrequencyInterval -lt 1 -or $FrequencyInterval -ge 365) -and (-not ($FrequencyInterval -eq "EveryDay")) -and (-not $Force)) {
            Stop-Function -Message "The daily frequency type requires a frequency interval to be between 1 and 365 or 'EveryDay'." -Target $SqlInstance -FunctionName Set-DbaAgentSchedule
            return
        }

        # Check if the recurrence factor is set for weekly or monthly interval
        if ($FrequencyRecurrenceFactor -and ($FrequencyType -in 8, 16) -and $FrequencyRecurrenceFactor -lt 1) {
            if ($Force) {
                $FrequencyRecurrenceFactor = 1
                Write-Message -Message "Recurrence factor not set for weekly or monthly interval. Setting it to $FrequencyRecurrenceFactor." -Level Verbose -FunctionName Set-DbaAgentSchedule -ModuleName "dbatools"
            } else {
                Stop-Function -Message "The recurrence factor $FrequencyRecurrenceFactor needs to be at least on when using a weekly or monthly interval." -Target $SqlInstance -FunctionName Set-DbaAgentSchedule
                return
            }
        }

        # Check the subday interval
        if (($FrequencySubdayType -in 2, "Seconds", 4, "Minutes") -and (-not ($FrequencySubdayInterval -ge 1 -or $FrequencySubdayInterval -le 59))) {
            Stop-Function -Message "Subday interval $FrequencySubdayInterval must be between 1 and 59 when subday type is 'Seconds' or 'Minutes'" -Target $SqlInstance -FunctionName Set-DbaAgentSchedule
            return
        } elseif (($FrequencySubdayType -eq 8, "Hours") -and (-not ($FrequencySubdayInterval -ge 1 -and $FrequencySubdayInterval -le 23))) {
            Stop-Function -Message "Subday interval $FrequencySubdayInterval must be between 1 and 23 when subday type is 'Hours'" -Target $SqlInstance -FunctionName Set-DbaAgentSchedule
            return
        }

        # Check of the FrequencyInterval value is of type string and set the integer value
        if (($null -ne $FrequencyType)) {
            # Create the interval to hold the value(s)
            [int]$Interval = 0

            # If the FrequencyInterval is set for the daily FrequencyType
            if ($FrequencyType -eq 4) {
                # Create the interval to hold the value(s)
                [int]$interval = 1

                if ($FrequencyInterval -and $FrequencyInterval[0].GetType().Name -eq 'Int32') {
                    $interval = $FrequencyInterval[0]
                }
            }

            # If the FrequencyInterval is set for the weekly FrequencyType
            if ($FrequencyType -in 8, 'Weekly') {
                # Loop through the array
                foreach ($Item in $FrequencyInterval) {
                    switch ($Item) {
                        "Sunday" { $Interval += 1 }
                        "Monday" { $Interval += 2 }
                        "Tuesday" { $Interval += 4 }
                        "Wednesday" { $Interval += 8 }
                        "Thursday" { $Interval += 16 }
                        "Friday" { $Interval += 32 }
                        "Saturday" { $Interval += 64 }
                        "Weekdays" { $Interval = 62 }
                        "Weekend" { $Interval = 65 }
                        "EveryDay" { $Interval = 127 }
                        1 { $Interval += 1 }
                        2 { $Interval += 2 }
                        4 { $Interval += 4 }
                        8 { $Interval += 8 }
                        16 { $Interval += 16 }
                        32 { $Interval += 32 }
                        64 { $Interval += 64 }
                        62 { $Interval = 62 }
                        65 { $Interval = 65 }
                        127 { $Interval = 127 }
                    }
                }
            }

            # If the FrequencyInterval is set for the monthly FrequencyInterval
            if ($FrequencyType -in 16, 'Monthly') {
                # Create the interval to hold the value(s)
                [int]$interval = 0

                # Loop through the array
                foreach ($item in $FrequencyInterval) {
                    switch ($item) {
                        { [int]$_ -ge 1 -and [int]$_ -le 31 } { $interval = [int]$item }
                    }
                }
            }

            # If the FrequencyInterval is set for the relative monthly FrequencyInterval
            if ($FrequencyType -in 32, 'MonthlyRelative') {
                # Loop through the array
                foreach ($Item in $FrequencyInterval) {
                    switch ($Item) {
                        "Sunday" { $Interval += 1 }
                        "Monday" { $Interval += 2 }
                        "Tuesday" { $Interval += 3 }
                        "Wednesday" { $Interval += 4 }
                        "Thursday" { $Interval += 5 }
                        "Friday" { $Interval += 6 }
                        "Saturday" { $Interval += 7 }
                        "Day" { $Interval += 8 }
                        "Weekday" { $Interval += 9 }
                        "WeekendDay" { $Interval += 10 }
                        1 { $Interval += 1 }
                        2 { $Interval += 2 }
                        3 { $Interval += 3 }
                        4 { $Interval += 4 }
                        5 { $Interval += 5 }
                        6 { $Interval += 6 }
                        7 { $Interval += 7 }
                        8 { $Interval += 8 }
                        9 { $Interval += 9 }
                        10 { $Interval += 10 }
                    }
                }
            }
        }

        # Check of the relative FrequencyInterval value is of type string and set the integer value
        if (($FrequencyRelativeInterval -notin 1, 2, 4, 8, 16) -and ($null -ne $FrequencyRelativeInterval)) {
            [int]$FrequencyRelativeInterval =
            switch ($FrequencyRelativeInterval) {
                "First" { 1 }
                "Second" { 2 }
                "Third" { 4 }
                "Fourth" { 8 }
                "Last" { 16 }
                "Unused" { 0 }
                default { 0 }
            }
        }

        # Setup the regex
        $RegexDate = '(?<!\d)(?:(?:(?:1[6-9]|[2-9]\d)?\d{2})(?:(?:(?:0[13578]|1[02])31)|(?:(?:0[1,3-9]|1[0-2])(?:29|30)))|(?:(?:(?:(?:1[6-9]|[2-9]\d)?(?:0[48]|[2468][048]|[13579][26])|(?:(?:16|[2468][048]|[3579][26])00)))0229)|(?:(?:1[6-9]|[2-9]\d)?\d{2})(?:(?:0?[1-9])|(?:1[0-2]))(?:0?[1-9]|1\d|2[0-8]))(?!\d)'
        $RegexTime = '^(?:(?:([01]?\d|2[0-3]))?([0-5]?\d))?([0-5]?\d)$'

        # Check the start date
        if ($StartDate -and ($StartDate -notmatch $RegexDate)) {
            Stop-Function -Message "Start date $StartDate needs to be a valid date with format yyyyMMdd" -Target $SqlInstance -FunctionName Set-DbaAgentSchedule
            return
        }

        # Check the end date
        if ($EndDate -and ($EndDate -notmatch $RegexDate)) {
            Stop-Function -Message "End date $EndDate needs to be a valid date with format yyyyMMdd" -Target $SqlInstance -FunctionName Set-DbaAgentSchedule
            return
        } elseif ($EndDate -and ($EndDate -lt $StartDate)) {
            Stop-Function -Message "End date $EndDate cannot be before start date $StartDate" -Target $SqlInstance -FunctionName Set-DbaAgentSchedule
            return
        }

        # Check the start time
        if ($StartTime -and ($StartTime -notmatch $RegexTime)) {
            Stop-Function -Message "Start time $StartTime needs to match between '000000' and '235959'. Schedule $Schedule not set." -Target $SqlInstance -FunctionName Set-DbaAgentSchedule
            return
        }

        # Check the end time
        if ($EndTime -and ($EndTime -notmatch $RegexTime)) {
            Stop-Function -Message "End time $EndTime needs to match between '000000' and '235959'. Schedule $Schedule not set." -Target $SqlInstance -FunctionName Set-DbaAgentSchedule
            return
        }

        #Format dates and times
        if ($StartDate) {
            $StartDate = $StartDate.Insert(6, '-').Insert(4, '-')
        }
        if ($EndDate) {
            $EndDate = $EndDate.Insert(6, '-').Insert(4, '-')
        }
        if ($StartTime) {
            $StartTime = $StartTime.Insert(4, ':').Insert(2, ':')
        }
        if ($EndTime) {
            $EndTime = $EndTime.Insert(4, ':').Insert(2, ':')
        }
    }
    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __setDbaAgentScheduleBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value); FrequencyType = $FrequencyType; FrequencySubdayType = $FrequencySubdayType; Interval = $Interval; FrequencyRelativeInterval = $FrequencyRelativeInterval; FrequencyRecurrenceFactor = $FrequencyRecurrenceFactor; StartDate = $StartDate; EndDate = $EndDate; StartTime = $StartTime; EndTime = $EndTime } }
} $SqlInstance $Schedule $FrequencyType $FrequencyInterval $FrequencySubdayType $FrequencySubdayInterval $FrequencyRelativeInterval $FrequencyRecurrenceFactor $StartDate $EndDate $StartTime $EndTime $Force $EnableException @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM apart from $Pscmdlet.ShouldProcess / $PSCmdlet.ShouldProcess ->
    // $__gate.ShouldProcess and -FunctionName Set-DbaAgentSchedule on the direct Stop-Function/
    // Write-Message sites. The begin Force/ConfirmPreference line + gate selection are prepended. The
    // body is dot-sourced so the inner "return" after the Alter catch still reaches the $Interval
    // sentinel. The Test-FunctionInterrupt check is preserved verbatim but inert (the C# guard already
    // short-circuits an interrupted record; the process Stop-Functions are all -Continue so no
    // interrupt is set here).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Job, $Schedule, $NewName, $Enabled, $Disabled, $FrequencySubdayInterval, $FrequencyType, $Interval, $FrequencySubdayType, $FrequencyRelativeInterval, $FrequencyRecurrenceFactor, $StartDate, $EndDate, $StartTime, $EndTime, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Job, [string]$Schedule, [string]$NewName, $Enabled, $Disabled, [int]$FrequencySubdayInterval, $FrequencyType, $Interval, $FrequencySubdayType, $FrequencyRelativeInterval, $FrequencyRecurrenceFactor, $StartDate, $EndDate, $StartTime, $EndTime, $Force, $EnableException, $__realCmdlet)
    if ($Force) { $ConfirmPreference = 'none' }
    $__gate = if ($Force) { $PSCmdlet } else { $__realCmdlet }
    . {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaAgentSchedule
            }

            foreach ($j in $Job) {
                # Check if the job exists
                if ($server.JobServer.Jobs.Name -notcontains $j) {
                    Write-Message -Message "Job $j doesn't exists on $instance" -Level Warning -FunctionName Set-DbaAgentSchedule -ModuleName "dbatools"
                } else {
                    # Check if the job schedule exists
                    if ($server.JobServer.Jobs[$j].JobSchedules.Name -notcontains $Schedule) {
                        Stop-Function -Message "Schedule $Schedule doesn't exists for job $j on $instance" -Target $instance -Continue -FunctionName Set-DbaAgentSchedule
                    } else {
                        # Get the job schedule
                        # If for some reason the there are multiple schedules with the same name, the first on is chosen
                        $JobSchedule = $server.JobServer.Jobs[$j].JobSchedules[$Schedule][0]

                        # Set the frequency interval to make up for newly created schedules without an interval
                        if ($JobSchedule.FrequencyInterval -eq 0 -and $Interval -lt 1) {
                            $Interval = 1
                        }

                        #region job step options
                        # Setting the options for the job schedule
                        if ($NewName) {
                            if ($__gate.ShouldProcess($server, "Setting job schedule $Schedule Name to $NewName")) {
                                $JobSchedule.Rename($NewName)
                            }
                        }

                        if ($Enabled) {
                            Write-Message -Message "Setting job schedule to enabled for schedule $Schedule" -Level Verbose -FunctionName Set-DbaAgentSchedule -ModuleName "dbatools"
                            $JobSchedule.IsEnabled = $true
                        }

                        if ($Disabled) {
                            Write-Message -Message "Setting job schedule to disabled for schedule $Schedule" -Level Verbose -FunctionName Set-DbaAgentSchedule -ModuleName "dbatools"
                            $JobSchedule.IsEnabled = $false
                        }

                        if ($FrequencyType -ge 1) {
                            Write-Message -Message "Setting job schedule frequency to $FrequencyType for schedule $Schedule" -Level Verbose -FunctionName Set-DbaAgentSchedule -ModuleName "dbatools"
                            $JobSchedule.FrequencyTypes = $FrequencyType
                        }

                        if ($Interval -ge 1) {
                            Write-Message -Message "Setting job schedule frequency interval to $Interval for schedule $Schedule" -Level Verbose -FunctionName Set-DbaAgentSchedule -ModuleName "dbatools"
                            $JobSchedule.FrequencyInterval = $Interval
                        }

                        if ($FrequencySubdayType -ge 1) {
                            Write-Message -Message "Setting job schedule frequency subday type to $FrequencySubdayType for schedule $Schedule" -Level Verbose -FunctionName Set-DbaAgentSchedule -ModuleName "dbatools"
                            $JobSchedule.FrequencySubDayTypes = $FrequencySubdayType
                        }

                        if ($FrequencySubdayInterval -ge 1) {
                            Write-Message -Message "Setting job schedule frequency subday interval to $FrequencySubdayInterval for schedule $Schedule" -Level Verbose -FunctionName Set-DbaAgentSchedule -ModuleName "dbatools"
                            $JobSchedule.FrequencySubDayInterval = $FrequencySubdayInterval
                        }

                        if (($FrequencyRelativeInterval -ge 1) -and ($FrequencyType -eq 32)) {
                            Write-Message -Message "Setting job schedule frequency relative interval to $FrequencyRelativeInterval for schedule $Schedule" -Level Verbose -FunctionName Set-DbaAgentSchedule -ModuleName "dbatools"
                            $JobSchedule.FrequencyRelativeIntervals = $FrequencyRelativeInterval
                        }

                        if (($FrequencyRecurrenceFactor -ge 1) -and ($FrequencyType -in 8, 16, 32)) {
                            Write-Message -Message "Setting job schedule frequency recurrence factor to $FrequencyRecurrenceFactor for schedule $Schedule" -Level Verbose -FunctionName Set-DbaAgentSchedule -ModuleName "dbatools"
                            $JobSchedule.FrequencyRecurrenceFactor = $FrequencyRecurrenceFactor
                        }

                        if ($StartDate) {
                            Write-Message -Message "Setting job schedule start date to $StartDate for schedule $Schedule" -Level Verbose -FunctionName Set-DbaAgentSchedule -ModuleName "dbatools"
                            $JobSchedule.ActiveStartDate = $StartDate
                        }

                        if ($EndDate) {
                            Write-Message -Message "Setting job schedule end date to $EndDate for schedule $Schedule" -Level Verbose -FunctionName Set-DbaAgentSchedule -ModuleName "dbatools"
                            $JobSchedule.ActiveEndDate = $EndDate
                        }

                        if ($StartTime) {
                            Write-Message -Message "Setting job schedule start time to $StartTime for schedule $Schedule" -Level Verbose -FunctionName Set-DbaAgentSchedule -ModuleName "dbatools"
                            $JobSchedule.ActiveStartTimeOfDay = $StartTime
                        }

                        if ($EndTime) {
                            Write-Message -Message "Setting job schedule end time to $EndTime for schedule $Schedule" -Level Verbose -FunctionName Set-DbaAgentSchedule -ModuleName "dbatools"
                            $JobSchedule.ActiveEndTimeOfDay = $EndTime
                        }
                        #endregion job step options

                        # Execute the query
                        if ($__gate.ShouldProcess($instance, "Committing changes for schedule $Schedule for job $j on $instance")) {
                            try {
                                # Excute the query and save the result
                                Write-Message -Message "Committing changes for schedule $Schedule for job $j" -Level Verbose -FunctionName Set-DbaAgentSchedule -ModuleName "dbatools"

                                $JobSchedule.Alter()

                                # Refresh the cache to pick up the changes
                                $server.JobServer.SharedSchedules.Refresh()

                                # Return updated schedule
                                Get-DbaAgentSchedule -SqlInstance $server -ScheduleUid $JobSchedule.ScheduleUid
                            } catch {
                                Stop-Function -Message "Something went wrong changing the schedule" -Target $instance -ErrorRecord $_ -Continue -FunctionName Set-DbaAgentSchedule
                                return
                            }
                        }
                    }
                }
            } # foreach object job
        } # foreach object instance
    }
    @{ __setDbaAgentScheduleProcess = @{ Interval = $Interval } }
} $SqlInstance $SqlCredential $Job $Schedule $NewName $Enabled $Disabled $FrequencySubdayInterval $FrequencyType $Interval $FrequencySubdayType $FrequencyRelativeInterval $FrequencyRecurrenceFactor $StartDate $EndDate $StartTime $EndTime $Force $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM apart from -FunctionName Set-DbaAgentSchedule on the direct
    // Write-Message. The Test-FunctionInterrupt check is preserved verbatim but inert (the C#
    // EndProcessing guard already short-circuits an interrupted pipeline). $EnableException is
    // marshaled in for the scope-walk + a positional arg.
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
    Write-Message -Message "Finished changing the job schedule(s)" -Level Verbose -FunctionName Set-DbaAgentSchedule -ModuleName "dbatools"
} $EnableException @__commonParameters 3>&1 2>&1
""";
}

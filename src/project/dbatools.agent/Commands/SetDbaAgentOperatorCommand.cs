#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoAgentOperator = Microsoft.SqlServer.Management.Smo.Agent.Operator;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Modifies existing SQL Server Agent operators.
/// </summary>
/// <remarks>
/// The argument validation, the pager-day/time normalization, the failsafe computation, the operator
/// lookup, the property updates, the Alter, and the output all run the original dbatools PowerShell body
/// inside the dbatools module scope rather than being reimplemented in C#, so the engine decides the
/// observable details.
///
/// The six pager time parameters (SaturdayStartTime/EndTime, SundayStartTime/EndTime, WeekdayStartTime/
/// EndTime) span the pipeline in the source's shared process scope: the body reformats them in place
/// (inserting ':' separators) and, being non-pipeline parameters, they are NOT rebound per record, so a
/// later piped record sees the already-formatted value ("07:00:00"), which then fails the HHMMSS regex.
/// A per-record hop scope would reset them to the pristine bound value, so they are carried record-to-record
/// via a sentinel: C# fields seed the hop top and are re-emitted at the end. _seeded distinguishes the FIRST
/// record (which uses the bound parameter values) from later records (which use the carried, reformatted
/// values). $Interval and the failsafe enum are recomputed from scratch each record, so they are not carried.
///
/// The body is dot-sourced so the many early "return"s (missing address, missing operator, bad time format)
/// exit only the block and the state sentinel is still emitted, keeping the carry consistent. Output streams:
/// each altered operator is emitted before a later one may fail under -EnableException (DEF-001).
///
/// This cmdlet declares the ShouldProcess surface (ConfirmImpact Medium, no -Force), but the actual
/// ShouldProcess calls run against the inner advanced function's own $PSCmdlet inside the module-scoped hop.
/// Surface pinned by migration/baselines/Set-DbaAgentOperator.json.
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaAgentOperator", DefaultParameterSetName = "Default", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class SetDbaAgentOperatorCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name(s) of the existing SQL Agent operator to modify.</summary>
    [Parameter(Position = 2)]
    public string[]? Operator { get; set; }

    /// <summary>Renames the operator to this value.</summary>
    [Parameter(Position = 3)]
    public string? Name { get; set; }

    /// <summary>The email address for notifications.</summary>
    [Parameter(Position = 4)]
    public string? EmailAddress { get; set; }

    /// <summary>The network computer name for net send notifications.</summary>
    [Parameter(Position = 5)]
    public string? NetSendAddress { get; set; }

    /// <summary>The pager email address for urgent notifications.</summary>
    [Parameter(Position = 6)]
    public string? PagerAddress { get; set; }

    /// <summary>Which days pager notifications are active.</summary>
    [Parameter(Position = 7)]
    [PsStringCast]
    [ValidateSet("EveryDay", "Weekdays", "Weekend", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")]
    public string? PagerDay { get; set; }

    /// <summary>When pager notifications begin on Saturday (HHMMSS).</summary>
    [Parameter(Position = 8)]
    public string? SaturdayStartTime { get; set; }

    /// <summary>When pager notifications end on Saturday (HHMMSS).</summary>
    [Parameter(Position = 9)]
    public string? SaturdayEndTime { get; set; }

    /// <summary>When pager notifications begin on Sunday (HHMMSS).</summary>
    [Parameter(Position = 10)]
    public string? SundayStartTime { get; set; }

    /// <summary>When pager notifications end on Sunday (HHMMSS).</summary>
    [Parameter(Position = 11)]
    public string? SundayEndTime { get; set; }

    /// <summary>When pager notifications begin on weekdays (HHMMSS).</summary>
    [Parameter(Position = 12)]
    public string? WeekdayStartTime { get; set; }

    /// <summary>When pager notifications end on weekdays (HHMMSS).</summary>
    [Parameter(Position = 13)]
    public string? WeekdayEndTime { get; set; }

    /// <summary>Designates this operator as the failsafe operator.</summary>
    [Parameter]
    public SwitchParameter IsFailsafeOperator { get; set; }

    /// <summary>How the failsafe operator receives notifications.</summary>
    [Parameter(Position = 14)]
    [ValidateSet("None", "NotifyEmail", "Pager", "NetSend", "NotifyAll")]
    public string[] FailsafeNotificationMethod { get; set; } = new[] { "NotifyEmail" };

    /// <summary>Agent operator objects piped in from Get-DbaAgentOperator.</summary>
    [Parameter(ValueFromPipeline = true, Position = 15)]
    public SmoAgentOperator[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (all params are in
    // __AllParameterSets; only the cmdlet-level DefaultParameterSetName names "Default"), so the inherited
    // [Parameter] already matches; no per-set override needed.

    // The six pager time parameters carried across records (the source reformats them in place and keeps
    // them in the shared process scope). _seeded distinguishes the first record (bound values) from later
    // records (carried, reformatted values).
    private bool _seeded;
    private string? _saturdayStartTime;
    private string? _saturdayEndTime;
    private string? _sundayStartTime;
    private string? _sundayEndTime;
    private string? _weekdayStartTime;
    private string? _weekdayEndTime;

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__setDbaAgentOperatorState"))
            {
                if (sentinel["__setDbaAgentOperatorState"] is Hashtable state)
                {
                    _saturdayStartTime = state["SaturdayStartTime"] as string;
                    _saturdayEndTime = state["SaturdayEndTime"] as string;
                    _sundayStartTime = state["SundayStartTime"] as string;
                    _sundayEndTime = state["SundayEndTime"] as string;
                    _weekdayStartTime = state["WeekdayStartTime"] as string;
                    _weekdayEndTime = state["WeekdayEndTime"] as string;
                    _seeded = true;
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
        }, BodyScript,
            SqlInstance, SqlCredential, Operator, Name, EmailAddress, NetSendAddress, PagerAddress, PagerDay,
            _seeded ? _saturdayStartTime : SaturdayStartTime,
            _seeded ? _saturdayEndTime : SaturdayEndTime,
            _seeded ? _sundayStartTime : SundayStartTime,
            _seeded ? _sundayEndTime : SundayEndTime,
            _seeded ? _weekdayStartTime : WeekdayStartTime,
            _seeded ? _weekdayEndTime : WeekdayEndTime,
            IsFailsafeOperator.ToBool(), FailsafeNotificationMethod, InputObject, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from $Pscmdlet.ShouldProcess -> $PSCmdlet.ShouldProcess and
    // -FunctionName Set-DbaAgentOperator on the direct Stop-Function/Write-Message sites. ShouldProcess routes
    // through the inner advanced function's OWN $PSCmdlet (declared SupportsShouldProcess + ConfirmImpact
    // Medium, driven by the splatted WhatIf/Confirm), never the host cmdlet - the host cmdlet's confirm-impact
    // read faults inside the nested pipeline at Medium, and uniform inner-$PSCmdlet routing at every level
    // matches what the source did. The six time parameters are seeded from the carried values at the top and
    // re-emitted in a sentinel at the end so the source's in-place reformat leak across records is reproduced.
    // The source's two $PSBoundParameters.<name> guard reads are rewritten to the plain parameter variables:
    // inside the dot-sourced (. { }) block $PSBoundParameters is a fresh empty automatic (dot-sourcing does not
    // inherit the enclosing function's bound set), and these are VALUE reads where bound-null and unbound-null
    // are indistinguishable and the params carry no defaults, so $EmailAddress etc. are exactly equivalent. The
    // body is dot-sourced so the early returns still emit the sentinel.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Operator, $Name, $EmailAddress, $NetSendAddress, $PagerAddress, $PagerDay, $SaturdayStartTime, $SaturdayEndTime, $SundayStartTime, $SundayEndTime, $WeekdayStartTime, $WeekdayEndTime, $IsFailsafeOperator, $FailsafeNotificationMethod, $InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$Operator, [string]$Name, [string]$EmailAddress, [string]$NetSendAddress, [string]$PagerAddress, [string]$PagerDay, [string]$SaturdayStartTime, [string]$SaturdayEndTime, [string]$SundayStartTime, [string]$SundayEndTime, [string]$WeekdayStartTime, [string]$WeekdayEndTime, $IsFailsafeOperator, [string[]]$FailsafeNotificationMethod, [Microsoft.SqlServer.Management.Smo.Agent.Operator[]]$InputObject, $EnableException, $__realCmdlet)
    . {
        if (-not $EmailAddress -and -not $NetSendAddress -and -not $PagerAddress) {
            Stop-Function -Message "You must specify either an EmailAddress, NetSendAddress, or a PagerAddress to be able to create an operator." -FunctionName Set-DbaAgentOperator
            return
        }

        if (-not $InputObject -and -not $Operator) {
            Stop-Function -Message "You must specify either operator or pipe in a list of operators" -FunctionName Set-DbaAgentOperator
            return
        }

        [int]$Interval = 0

        # Loop through the array
        foreach ($Item in $PagerDay) {
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
                default { $Interval = 0 }
            }
        }

        $RegexTime = '^(?:(?:([01]?\d|2[0-3]))?([0-5]?\d))?([0-5]?\d)$'

        if ($PagerDay -in ('Everyday', 'Saturday', 'Weekends')) {
            # Check the start time
            if (-not $SaturdayStartTime) {
                $SaturdayStartTime = '000000'
                Write-Message -Message "Saturday Start time was not set. Setting it to $SaturdayStartTime" -Level Verbose -FunctionName Set-DbaAgentOperator -ModuleName "dbatools"
            } elseif ($SaturdayStartTime -notmatch $RegexTime) {
                Stop-Function -Message "Start time $SaturdayStartTime needs to match between '000000' and '235959'" -FunctionName Set-DbaAgentOperator
                return
            }

            # Check the end time
            if (-not $SaturdayEndTime) {
                $SaturdayEndTime = '235959'
                Write-Message -Message "Saturday End time was not set. Setting it to $SaturdayEndTime" -Level Verbose -FunctionName Set-DbaAgentOperator -ModuleName "dbatools"
            } elseif ($SaturdayEndTime -notmatch $RegexTime) {
                Stop-Function -Message "End time $SaturdayEndTime needs to match between '000000' and '235959'" -FunctionName Set-DbaAgentOperator
                return
            }
        }

        if ($PagerDay -in ('Everyday', 'Sunday', 'Weekends')) {
            # Check the start time
            if (-not $SundayStartTime) {
                $SundayStartTime = '000000'
                Write-Message -Message "Sunday Start time was not set. Setting it to $SundayStartTime" -Level Verbose -FunctionName Set-DbaAgentOperator -ModuleName "dbatools"
            } elseif ($SundayStartTime -notmatch $RegexTime) {
                Stop-Function -Message "Start time $SundayStartTime needs to match between '000000' and '235959'" -FunctionName Set-DbaAgentOperator
                return
            }

            # Check the end time
            if (-not $SundayEndTime) {
                $SundayEndTime = '235959'
                Write-Message -Message "Sunday End time was not set. Setting it to $SundayEndTime" -Level Verbose -FunctionName Set-DbaAgentOperator -ModuleName "dbatools"
            } elseif ($SundayEndTime -notmatch $RegexTime) {
                Stop-Function -Message "Sunday End time $SundayEndTime needs to match between '000000' and '235959'" -FunctionName Set-DbaAgentOperator
                return
            }
        }

        if ($PagerDay -in ('Everyday', 'Weekdays', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday')) {
            # Check the start time
            if (-not $WeekdayStartTime) {
                $WeekdayStartTime = '000000'
                Write-Message -Message "Weekday Start time was not set. Setting it to $WeekdayStartTime" -Level Verbose -FunctionName Set-DbaAgentOperator -ModuleName "dbatools"
            } elseif ($WeekdayStartTime -notmatch $RegexTime) {
                Stop-Function -Message "Weekday Start time $WeekdayStartTime needs to match between '000000' and '235959'" -FunctionName Set-DbaAgentOperator
                return
            }

            # Check the end time
            if (-not $WeekdayEndTime) {
                $WeekdayEndTime = '235959'
                Write-Message -Message "Weekday End time was not set. Setting it to $WeekdayEndTime" -Level Verbose -FunctionName Set-DbaAgentOperator -ModuleName "dbatools"
            } elseif ($WeekdayEndTime -notmatch $RegexTime) {
                Stop-Function -Message "Weekday End time $WeekdayEndTime needs to match between '000000' and '235959'" -FunctionName Set-DbaAgentOperator
                return
            }
        }

        if ($IsFailsafeOperator -and ($FailsafeNotificationMethod.Count -gt 1 -and ($FailsafeNotificationMethod.Contains('None') -or $FailsafeNotificationMethod.Contains('NotifyAll')))) {
            Stop-Function -Message "The failsafe operator notification methods 'None' and 'NotifyAll' cannot be specified in conjunction with any other notification method." -FunctionName Set-DbaAgentOperator
            return
        } else {

            [int]$failsafeNotificationMethodEnumerated = 0

            if ($FailsafeNotificationMethod.Contains('NotifyAll')) {
                $failsafeNotificationMethodEnumerated += 7
            } else {

                if ($FailsafeNotificationMethod.Contains('NotifyEmail')) {
                    $failsafeNotificationMethodEnumerated += 1
                }

                if ($FailsafeNotificationMethod.Contains('Pager')) {
                    $failsafeNotificationMethodEnumerated += 2
                }

                if ($FailsafeNotificationMethod.Contains('NetSend')) {
                    $failsafeNotificationMethodEnumerated += 4
                }
            }

        }

        #Format times
        if ($SaturdayStartTime) {
            $SaturdayStartTime = $SaturdayStartTime.Insert(4, ':').Insert(2, ':')
        }
        if ($SaturdayEndTime) {
            $SaturdayEndTime = $SaturdayEndTime.Insert(4, ':').Insert(2, ':')
        }

        if ($SundayStartTime) {
            $SundayStartTime = $SundayStartTime.Insert(4, ':').Insert(2, ':')
        }
        if ($SundayEndTime) {
            $SundayEndTime = $SundayEndTime.Insert(4, ':').Insert(2, ':')
        }

        if ($WeekdayStartTime) {
            $WeekdayStartTime = $WeekdayStartTime.Insert(4, ':').Insert(2, ':')
        }
        if ($WeekdayEndTime) {
            $WeekdayEndTime = $WeekdayEndTime.Insert(4, ':').Insert(2, ':')
        }

        if ($SqlInstance) {
            try {
                $InputObject += Get-DbaAgentOperator -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Operator $Operator -EnableException
            } catch {
                Stop-Function -Message "Failed" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaAgentOperator
            }
        }

        foreach ($op in $InputObject) {
            $server = $op | Get-ConnectionParent
            try {
                if ($Name) {
                    if ($PSCmdlet.ShouldProcess($server, "Updating Operator $($op.Name) Name to $Name")) {
                        # instead of using .Rename(), we will execute a sql script to avoid enumeration problems when piping
                        $sql = "EXEC msdb.dbo.sp_update_operator @name = N'$($op.Name)', @new_name = N'$Name'"
                        try {
                            Invoke-DbaQuery -SqlInstance $server -Query "$sql" -EnableException
                        } catch {
                            Stop-Function -Message "Failed on $($server.name)" -ErrorRecord $_ -Target $server -Continue -FunctionName Set-DbaAgentOperator
                        }
                        $server.JobServer.Operators.Refresh()
                        $op = Get-DbaAgentOperator -SqlInstance $server -Operator $Name
                    }
                }

                if ($EmailAddress) {
                    if ($PSCmdlet.ShouldProcess($server, "Updating Operator $($op.Name) EmailAddress to $EmailAddress")) {
                        $op.EmailAddress = $EmailAddress
                    }
                }

                if ($NetSendAddress) {
                    if ($PSCmdlet.ShouldProcess($server, "Updating Operator $($op.Name) NetSendAddress to $NetSendAddress")) {
                        $op.NetSendAddress = $NetSendAddress
                    }
                }

                if ($PagerAddress) {
                    if ($PSCmdlet.ShouldProcess($server, "Updating Operator $($op.Name) PagerAddress to $PagerAddress")) {
                        $op.PagerAddress = $PagerAddress
                    }
                }

                if ($Interval) {
                    if ($PSCmdlet.ShouldProcess($server, "Updating Operator $($op.Name) PagerDays to $Interval")) {
                        $op.PagerDays = $Interval
                    }
                }

                if ($SaturdayStartTime) {
                    if ($PSCmdlet.ShouldProcess($server, "Updating Operator $($op.Name) SaturdayPagerStartTime to $SaturdayStartTime")) {
                        $op.SaturdayPagerStartTime = $SaturdayStartTime
                    }
                }

                if ($SaturdayEndTime) {
                    if ($PSCmdlet.ShouldProcess($server, "Updating Operator $($op.Name) SaturdayPagerEndTime to $SaturdayEndTime")) {
                        $op.SaturdayPagerEndTime = $SaturdayEndTime
                    }
                }

                if ($SundayStartTime) {
                    if ($PSCmdlet.ShouldProcess($server, "Updating Operator $($op.Name) SundayPagerStartTime to $SundayStartTime")) {
                        $op.SundayPagerStartTime = $SundayStartTime
                    }
                }

                if ($SundayEndTime) {
                    if ($PSCmdlet.ShouldProcess($server, "Updating Operator $($op.Name) SundayPagerEndTime to $SundayEndTime")) {
                        $op.SundayPagerEndTime = $SundayEndTime
                    }
                }

                if ($WeekdayStartTime) {
                    if ($PSCmdlet.ShouldProcess($server, "Updating Operator $($op.Name) WeekdayPagerStartTime to $WeekdayStartTime")) {
                        $op.WeekdayPagerStartTime = $WeekdayStartTime
                    }
                }

                if ($WeekdayEndTime) {
                    if ($PSCmdlet.ShouldProcess($server, "Updating Operator $($op.Name) WeekdayPagerEndTime to $WeekdayEndTime")) {
                        $op.WeekdayPagerEndTime = $WeekdayEndTime
                    }
                }

                if ($IsFailsafeOperator) {
                    if ($PSCmdlet.ShouldProcess($server, "Updating FailSafe Operator to $operator")) {
                        $server.JobServer.AlertSystem.FailSafeOperator = $Operator
                        $server.JobServer.AlertSystem.NotificationMethod = $failsafeNotificationMethodEnumerated
                        $server.JobServer.AlertSystem.Alter()
                    }
                }

                if ($PSCmdlet.ShouldProcess($server, "Committing changes for Operator $($op.Name)")) {
                    $op.Alter()
                    $op
                }
            } catch {
                Stop-Function -Message "Issue creating operator." -Category InvalidOperation -ErrorRecord $_ -Target $server -FunctionName Set-DbaAgentOperator
            }
        }
    }

    @{ __setDbaAgentOperatorState = @{ SaturdayStartTime = $SaturdayStartTime; SaturdayEndTime = $SaturdayEndTime; SundayStartTime = $SundayStartTime; SundayEndTime = $SundayEndTime; WeekdayStartTime = $WeekdayStartTime; WeekdayEndTime = $WeekdayEndTime } }
} $SqlInstance $SqlCredential $Operator $Name $EmailAddress $NetSendAddress $PagerAddress $PagerDay $SaturdayStartTime $SaturdayEndTime $SundayStartTime $SundayEndTime $WeekdayStartTime $WeekdayEndTime $IsFailsafeOperator $FailsafeNotificationMethod $InputObject $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}

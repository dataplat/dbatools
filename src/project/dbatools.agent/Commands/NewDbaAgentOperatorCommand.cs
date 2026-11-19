#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoServer = Microsoft.SqlServer.Management.Smo.Server;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a new SQL Server Agent operator.
/// </summary>
/// <remarks>
/// The argument validation, the pager-day/time normalization, the instance connection, the existing-operator
/// / -Force handling, the SMO operator construction, the property assignments, the Create, the failsafe
/// configuration, and the output all run the original dbatools PowerShell body inside the dbatools module
/// scope rather than being reimplemented in C#, so the engine decides the observable details.
///
/// The six pager time parameters (SaturdayStartTime/EndTime, SundayStartTime/EndTime, WeekdayStartTime/
/// EndTime) span the pipeline in the source's shared process scope: the body reformats them in place
/// (inserting ':' separators) and, being non-pipeline parameters, they are NOT rebound per record, so a
/// later piped record sees the already-formatted value ("07:00:00") which then fails the HHMMSS regex.
/// A per-record hop scope would reset them to the pristine bound value, so they are carried record-to-record
/// via a sentinel: C# fields seed the hop and are re-emitted at the end. _seeded distinguishes the FIRST
/// record (bound parameter values) from later records (carried, reformatted values). $Interval is recomputed
/// from scratch each record, so it is not carried; $operators is created and used entirely within a single
/// ShouldProcess-gated block (never read before creation), so it does not leak.
///
/// The begin block's "if (\$Force) { \$ConfirmPreference = 'none' }" is folded into the top of the process
/// hop with \$__gate = if (\$Force) { \$PSCmdlet } else { \$__realCmdlet }; the three ShouldProcess sites route
/// through \$__gate so -Force suppresses the prompts. -Force is also read by value (the time-default branches
/// and the drop-existing check). The body is dot-sourced so the many early returns still emit the sentinel.
/// The "\$null -eq \$EmailAddress" value guards work verbatim (the passed value equals the real one). The
/// validations use no-Continue Stop-Functions that set the function-scope interrupt, but nothing reads
/// Test-FunctionInterrupt (inert); the return exits the hop, and under -EnableException they throw.
///
/// Output streams: each created operator is emitted before a later one may fail under -EnableException
/// (DEF-001). Surface pinned by migration/baselines/New-DbaAgentOperator.json.
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaAgentOperator", DefaultParameterSetName = "Default", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class NewDbaAgentOperatorCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name of the operator to create.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [PsStringCast]
    public string Operator { get; set; } = null!;

    /// <summary>The email address for notifications.</summary>
    [Parameter(Position = 3)]
    public string? EmailAddress { get; set; }

    /// <summary>The network computer name for net send notifications.</summary>
    [Parameter(Position = 4)]
    public string? NetSendAddress { get; set; }

    /// <summary>The pager email address for urgent notifications.</summary>
    [Parameter(Position = 5)]
    public string? PagerAddress { get; set; }

    /// <summary>Which days pager notifications are active.</summary>
    [Parameter(Position = 6)]
    [PsStringCast]
    [ValidateSet("EveryDay", "Weekdays", "Weekend", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")]
    public string? PagerDay { get; set; }

    /// <summary>When pager notifications begin on Saturday (HHMMSS).</summary>
    [Parameter(Position = 7)]
    public string? SaturdayStartTime { get; set; }

    /// <summary>When pager notifications end on Saturday (HHMMSS).</summary>
    [Parameter(Position = 8)]
    public string? SaturdayEndTime { get; set; }

    /// <summary>When pager notifications begin on Sunday (HHMMSS).</summary>
    [Parameter(Position = 9)]
    public string? SundayStartTime { get; set; }

    /// <summary>When pager notifications end on Sunday (HHMMSS).</summary>
    [Parameter(Position = 10)]
    public string? SundayEndTime { get; set; }

    /// <summary>When pager notifications begin on weekdays (HHMMSS).</summary>
    [Parameter(Position = 11)]
    public string? WeekdayStartTime { get; set; }

    /// <summary>When pager notifications end on weekdays (HHMMSS).</summary>
    [Parameter(Position = 12)]
    public string? WeekdayEndTime { get; set; }

    /// <summary>Designates this operator as the failsafe operator.</summary>
    [Parameter]
    public SwitchParameter IsFailsafeOperator { get; set; }

    /// <summary>How the failsafe operator receives notifications.</summary>
    [Parameter(Position = 13)]
    public string FailsafeNotificationMethod { get; set; } = "NotifyEmail";

    /// <summary>Drops and recreates the operator if one with the same name already exists.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>SMO Server objects piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 14)]
    public SmoServer[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (all params are in
    // __AllParameterSets; only the cmdlet-level DefaultParameterSetName names "Default"), so the inherited
    // [Parameter] already matches; no per-set override needed.

    // The six pager time parameters carried across records (the source reformats them in place and keeps them
    // in the shared process scope). _seeded distinguishes the first record (bound values) from later records.
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
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaAgentOperatorState"))
            {
                if (sentinel["__newDbaAgentOperatorState"] is Hashtable state)
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
            SqlInstance, SqlCredential, Operator, EmailAddress, NetSendAddress, PagerAddress, PagerDay,
            _seeded ? _saturdayStartTime : SaturdayStartTime,
            _seeded ? _saturdayEndTime : SaturdayEndTime,
            _seeded ? _sundayStartTime : SundayStartTime,
            _seeded ? _sundayEndTime : SundayEndTime,
            _seeded ? _weekdayStartTime : WeekdayStartTime,
            _seeded ? _weekdayEndTime : WeekdayEndTime,
            IsFailsafeOperator.ToBool(), FailsafeNotificationMethod, Force.ToBool(), InputObject,
            EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from $Pscmdlet.ShouldProcess -> $__gate.ShouldProcess and
    // -FunctionName New-DbaAgentOperator on the direct Stop-Function/Write-Message sites. The begin's
    // Force/ConfirmPreference line and the gate selection are prepended. The six time params arrive already
    // carried (C# passes the seeded values) and are re-emitted in a sentinel at the end so the source's
    // in-place reformat leak across records is reproduced. The body is dot-sourced so the early returns still
    // emit the sentinel.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Operator, $EmailAddress, $NetSendAddress, $PagerAddress, $PagerDay, $SaturdayStartTime, $SaturdayEndTime, $SundayStartTime, $SundayEndTime, $WeekdayStartTime, $WeekdayEndTime, $IsFailsafeOperator, $FailsafeNotificationMethod, $Force, $InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string]$Operator, [string]$EmailAddress, [string]$NetSendAddress, [string]$PagerAddress, [string]$PagerDay, [string]$SaturdayStartTime, [string]$SaturdayEndTime, [string]$SundayStartTime, [string]$SundayEndTime, [string]$WeekdayStartTime, [string]$WeekdayEndTime, $IsFailsafeOperator, [string]$FailsafeNotificationMethod, $Force, [Microsoft.SqlServer.Management.Smo.Server[]]$InputObject, $EnableException, $__realCmdlet)
    if ($Force) { $ConfirmPreference = 'none' }
    $__gate = if ($Force) { $PSCmdlet } else { $__realCmdlet }
    . {
        if ($null -eq $EmailAddress -and $null -eq $NetSendAddress -and $null -eq $PagerAddress) {
            Stop-Function -Message "You must specify either an EmailAddress, NetSendAddress, or a PagerAddress to be able to create an operator." -FunctionName New-DbaAgentOperator
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
            if (-not $SaturdayStartTime -and $Force) {
                $SaturdayStartTime = '000000'
                Write-Message -Message "Saturday Start time was not set. Force is being used. Setting it to $SaturdayStartTime" -Level Verbose -FunctionName New-DbaAgentOperator -ModuleName "dbatools"
            } elseif (-not $SaturdayStartTime) {
                Stop-Function -Message "Please enter Saturday start time or use -Force to use defaults." -FunctionName New-DbaAgentOperator
                return
            } elseif ($SaturdayStartTime -notmatch $RegexTime) {
                Stop-Function -Message "Start time $SaturdayStartTime needs to match between '000000' and '235959'. Pager Day not set." -FunctionName New-DbaAgentOperator
                return
            }

            # Check the end time
            if (-not $SaturdayEndTime -and $Force) {
                $SaturdayEndTime = '235959'
                Write-Message -Message "Saturday End time was not set. Force is being used. Setting it to $SaturdayEndTime" -Level Verbose -FunctionName New-DbaAgentOperator -ModuleName "dbatools"
            } elseif (-not $SaturdayEndTime) {
                Stop-Function -Message "Please enter a Saturday end time or use -Force to use defaults." -FunctionName New-DbaAgentOperator
                return
            } elseif ($SaturdayEndTime -notmatch $RegexTime) {
                Stop-Function -Message "End time $SaturdayEndTime needs to match between '000000' and '235959'. Pager Day not set." -FunctionName New-DbaAgentOperator
                return
            }
        }

        if ($PagerDay -in ('Everyday', 'Sunday', 'Weekends')) {
            # Check the start time
            if (-not $SundayStartTime -and $Force) {
                $SundayStartTime = '000000'
                Write-Message -Message "Sunday Start time was not set. Force is being used. Setting it to $SundayStartTime" -Level Verbose -FunctionName New-DbaAgentOperator -ModuleName "dbatools"
            } elseif (-not $SundayStartTime) {
                Stop-Function -Message "Please enter a Sunday start time or use -Force to use defaults." -FunctionName New-DbaAgentOperator
                return
            } elseif ($SundayStartTime -notmatch $RegexTime) {
                Stop-Function -Message "Start time $SundayStartTime needs to match between '000000' and '235959'. Pager Day not set." -FunctionName New-DbaAgentOperator
                return
            }

            # Check the end time
            if (-not $SundayEndTime -and $Force) {
                $SundayEndTime = '235959'
                Write-Message -Message "Sunday End time was not set. Force is being used. Setting it to $SundayEndTime" -Level Verbose -FunctionName New-DbaAgentOperator -ModuleName "dbatools"
            } elseif (-not $SundayEndTime) {
                Stop-Function -Message "Please enter a Sunday End Time or use -Force to use defaults." -FunctionName New-DbaAgentOperator
                return
            } elseif ($SundayEndTime -notmatch $RegexTime) {
                Stop-Function -Message "Sunday End time $SundayEndTime needs to match between '000000' and '235959'. Pager Day not set." -FunctionName New-DbaAgentOperator
                return
            }
        }

        if ($PagerDay -in ('Everyday', 'Weekdays', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday')) {
            # Check the start time
            if (-not $WeekdayStartTime -and $Force) {
                $WeekdayStartTime = '000000'
                Write-Message -Message "Weekday Start time was not set. Force is being used. Setting it to $WeekdayStartTime" -Level Verbose -FunctionName New-DbaAgentOperator -ModuleName "dbatools"
            } elseif (-not $WeekdayStartTime) {
                Stop-Function -Message "Please enter Weekday Start Time or use -Force to use defaults." -FunctionName New-DbaAgentOperator
                return
            } elseif ($WeekdayStartTime -notmatch $RegexTime) {
                Stop-Function -Message "Weekday Start time $WeekdayStartTime needs to match between '000000' and '235959'. Pager Day not set." -FunctionName New-DbaAgentOperator
                return
            }

            # Check the end time
            if (-not $WeekdayEndTime -and $Force) {
                $WeekdayEndTime = '235959'
                Write-Message -Message "Weekday End time was not set. Force is being used. Setting it to $WeekdayEndTime" -Level Verbose -FunctionName New-DbaAgentOperator -ModuleName "dbatools"
            } elseif (-not $WeekdayEndTime) {
                Stop-Function -Message "Please enter a Weekday End Time or use -Force to use defaults." -FunctionName New-DbaAgentOperator
                return
            } elseif ($WeekdayEndTime -notmatch $RegexTime) {
                Stop-Function -Message "Weekday End time $WeekdayEndTime needs to match between '000000' and '235959'. Pager Day not set." -FunctionName New-DbaAgentOperator
                return
            }
        }

        if ($IsFailsafeOperator -and ($FailsafeNotificationMethod -notin ('NotifyEmail', 'NotifyPager'))) {
            Stop-Function -Message "You must specify a notifiation method for the failsafe operator." -FunctionName New-DbaAgentOperator
            return
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

        foreach ($instance in $SqlInstance) {
            try {
                $InputObject += Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaAgentOperator
            }
        }

        foreach ($server in $InputObject) {
            $failsafe = $server.JobServer.AlertSystem | Select-Object FailsafeOperator

            if ((Get-DbaAgentOperator -SqlInstance $server -Operator $Operator).Count -ne 0) {
                if ($force -eq $false) {
                    if ($__gate.ShouldProcess($server, "Operator $operator exists at $server. Use -Force to drop and and create it.")) {
                        Write-Message -Level Verbose -Message "Operator $operator exists at $server. Use -Force to drop and create." -FunctionName New-DbaAgentOperator -ModuleName "dbatools"
                    }
                    continue
                } else {
                    if ($failsafe.FailsafeOperator -eq $operator -and $IsFailsafeOperator) {
                        Write-Message -Level Verbose -Message "$operator is the failsafe operator. Skipping drop." -FunctionName New-DbaAgentOperator -ModuleName "dbatools"
                        continue
                    }

                    if ($__gate.ShouldProcess($server, "Dropping operator $operator")) {
                        try {
                            Write-Message -Level Verbose -Message "Dropping Operator $operator" -FunctionName New-DbaAgentOperator -ModuleName "dbatools"
                            $server.JobServer.Operators[$operator].Drop()
                        } catch {
                            Stop-Function -Message "Issue dropping operator" -Category InvalidOperation -ErrorRecord $_ -Target $server -Continue -FunctionName New-DbaAgentOperator
                        }
                    }
                }
            }

            if ($__gate.ShouldProcess($server, "Creating Operator $operator")) {
                try {
                    $JobServer = $server.JobServer
                    $operators = $JobServer.Operators
                    try {
                        $operators = New-Object Microsoft.SqlServer.Management.Smo.Agent.Operator( $JobServer, $Operator)
                    } catch {
                        if ($_.Exception.Message -match "newParent") {
                            Stop-Function -Message "Cannot create agent operator through a contained availability group listener. SQL Server Agent objects are instance-level and must be managed on the instance directly. Please connect to the primary replica instead of the listener. Use Get-DbaAvailabilityGroup to find the current primary replica." -ErrorRecord $_ -Target $server -FunctionName New-DbaAgentOperator
                            return
                        } else {
                            throw
                        }
                    }

                    if ($EmailAddress) {
                        $operators.EmailAddress = $EmailAddress
                    }

                    if ($NetSendAddress) {
                        $operators.NetSendAddress = $NetSendAddress
                    }

                    if ($PagerAddress) {
                        $operators.PagerAddress = $PagerAddress
                    }

                    if ($Interval) {
                        $operators.PagerDays = $Interval
                    }

                    if ($SaturdayStartTime) {
                        $operators.SaturdayPagerStartTime = $SaturdayStartTime
                    }

                    if ($SaturdayEndTime) {
                        $operators.SaturdayPagerEndTime = $SaturdayEndTime
                    }

                    if ($SundayStartTime) {
                        $operators.SundayPagerStartTime = $SundayStartTime
                    }

                    if ($SundayEndTime) {
                        $operators.SundayPagerEndTime = $SundayEndTime
                    }

                    if ($WeekdayStartTime) {
                        $operators.WeekdayPagerStartTime = $WeekdayStartTime
                    }

                    if ($WeekdayEndTime) {
                        $operators.WeekdayPagerEndTime = $WeekdayEndTime
                    }

                    $operators.Create()

                    if ($IsFailsafeOperator) {
                        $server.JobServer.AlertSystem.FailSafeOperator = $Operator
                        $server.JobServer.AlertSystem.FailSafeOperator.NotificationMethod = $FailsafeNotificationMethod
                        $server.JobServer.AlertSystem.Alter()
                    }

                    Write-Message -Level Verbose -Message "Creating Operator $operator" -FunctionName New-DbaAgentOperator -ModuleName "dbatools"
                    Get-DbaAgentOperator -SqlInstance $server -Operator $Operator
                } catch {
                    Stop-Function -Message "Issue creating operator." -Category InvalidOperation -ErrorRecord $_ -Target $server -FunctionName New-DbaAgentOperator
                }
            }
        }
    }

    @{ __newDbaAgentOperatorState = @{ SaturdayStartTime = $SaturdayStartTime; SaturdayEndTime = $SaturdayEndTime; SundayStartTime = $SundayStartTime; SundayEndTime = $SundayEndTime; WeekdayStartTime = $WeekdayStartTime; WeekdayEndTime = $WeekdayEndTime } }
} $SqlInstance $SqlCredential $Operator $EmailAddress $NetSendAddress $PagerAddress $PagerDay $SaturdayStartTime $SaturdayEndTime $SundayStartTime $SundayEndTime $WeekdayStartTime $WeekdayEndTime $IsFailsafeOperator $FailsafeNotificationMethod $Force $InputObject $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}

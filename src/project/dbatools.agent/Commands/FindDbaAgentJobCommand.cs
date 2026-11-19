#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Searches SQL Agent jobs using the legacy command's independent filter semantics. Port of
/// public/Find-DbaAgentJob.ps1 (W2-009). The workflow remains a module-scoped PowerShell
/// compatibility hop so Get-JobList wildcard expansion, later-filter precedence, SMO adapter
/// behavior, output decoration, and dbatools stream/error handling stay observable-identical.
/// Surface pinned by migration/baselines/Find-DbaAgentJob.json.
/// </summary>
[Cmdlet(VerbsCommon.Find, "DbaAgentJob")]
public sealed class FindDbaAgentJobCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Job-name filters, including wildcard patterns.</summary>
    [Parameter(Position = 2)]
    [Alias("Name")]
    public string[]? JobName { get; set; }

    /// <summary>Exact job names to exclude from the final result.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeJobName { get; set; }

    /// <summary>Job-step name filters, including wildcard patterns.</summary>
    [Parameter(Position = 4)]
    public string[]? StepName { get; set; }

    /// <summary>Find jobs whose last run is at least this many days old.</summary>
    [Parameter(Position = 5)]
    public int LastUsed { get; set; }

    /// <summary>Find disabled jobs.</summary>
    [Parameter]
    [Alias("Disabled")]
    public SwitchParameter IsDisabled { get; set; }

    /// <summary>Find jobs whose last run failed.</summary>
    [Parameter]
    [Alias("Failed")]
    public SwitchParameter IsFailed { get; set; }

    /// <summary>Find jobs without an attached schedule.</summary>
    [Parameter]
    [Alias("NoSchedule")]
    public SwitchParameter IsNotScheduled { get; set; }

    /// <summary>Find jobs without an email operator.</summary>
    [Parameter]
    [Alias("NoEmailNotification")]
    public SwitchParameter IsNoEmailNotification { get; set; }

    /// <summary>Find jobs in these categories.</summary>
    [Parameter(Position = 6)]
    public string[]? Category { get; set; }

    /// <summary>Find jobs owned by this login, or exclude it when prefixed with a dash.</summary>
    [Parameter(Position = 7)]
    public string? Owner { get; set; }

    /// <summary>Find jobs whose last run is on or after this value.</summary>
    [Parameter(Position = 8)]
    [PsDateTimeCast]
    public DateTime Since { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private bool _beginInterrupted;

    protected override void BeginProcessing()
    {
        bool completed = false;
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            JobName, StepName, LastUsed, IsDisabled.ToBool(), IsFailed.ToBool(),
            IsNotScheduled.ToBool(), IsNoEmailNotification.ToBool(), Category, Owner,
            ExcludeJobName, EnableException.ToBool()))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__FindDbaAgentJobBeginComplete"]?.Value))
            {
                completed = true;
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }
        _beginInterrupted = !completed;
    }

    protected override void ProcessRecord()
    {
        if (_beginInterrupted)
            return;

        object? since = TestBound(nameof(Since)) ? Since : null;
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
            SqlInstance, SqlCredential, JobName, ExcludeJobName, StepName, LastUsed,
            IsDisabled.ToBool(), IsFailed.ToBool(), IsNotScheduled.ToBool(),
            IsNoEmailNotification.ToBool(), Category, Owner, since,
            EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"),
            NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string BeginScript = """
param($JobName, $StepName, $LastUsed, $IsDisabled, $IsFailed, $IsNotScheduled, $IsNoEmailNotification, $Category, $Owner, $ExcludeJobName, $EnableException)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param([string[]]$JobName, [string[]]$StepName, [int]$LastUsed, $IsDisabled, $IsFailed, $IsNotScheduled, $IsNoEmailNotification, [string[]]$Category, [string]$Owner, [string[]]$ExcludeJobName, $EnableException)
    if ($IsFailed, [boolean]$JobName, [boolean]$StepName, [boolean]$LastUsed.ToString(), $IsDisabled, $IsNotScheduled, $IsNoEmailNotification, [boolean]$Category, [boolean]$Owner, [boolean]$ExcludeJobName -notcontains $true) {
        Stop-Function -Message "At least one search term must be specified" -FunctionName Find-DbaAgentJob
    }
    if (-not (Test-FunctionInterrupt)) {
        [pscustomobject]@{ __FindDbaAgentJobBeginComplete = $true }
    }
} $JobName $StepName $LastUsed $IsDisabled $IsFailed $IsNotScheduled $IsNoEmailNotification $Category $Owner $ExcludeJobName $EnableException 3>&1 2>&1
""";

    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $JobName, $ExcludeJobName, $StepName, $LastUsed, $IsDisabled, $IsFailed, $IsNotScheduled, $IsNoEmailNotification, $Category, $Owner, $Since, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$JobName, [string[]]$ExcludeJobName, [string[]]$StepName, [int]$LastUsed, $IsDisabled, $IsFailed, $IsNotScheduled, $IsNoEmailNotification, [string[]]$Category, [string]$Owner, $Since, $EnableException, $__boundVerbose, $__boundDebug)

    if (Test-FunctionInterrupt) { return }

    foreach ($instance in $SqlInstance) {
        Write-Message -Level Verbose -Message "Running Scan on: $instance" -FunctionName Find-DbaAgentJob -ModuleName "dbatools"

        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Find-DbaAgentJob
        }

        $output = @()

        if ($JobName) {
            Write-Message -Level Verbose -Message "Retrieving jobs by their name." -FunctionName Find-DbaAgentJob -ModuleName "dbatools"
            $jobs = Get-JobList -SqlInstance $server -JobFilter $JobName
            $output = $jobs
        }

        if ($StepName) {
            Write-Message -Level Verbose -Message "Retrieving jobs by their step names." -FunctionName Find-DbaAgentJob -ModuleName "dbatools"
            $jobs = Get-JobList -SqlInstance $server -StepFilter $StepName
            $output = $jobs
        }

        if ( -not ($JobName -or $StepName)) {
            Write-Message -Level Verbose -Message "Retrieving all jobs" -FunctionName Find-DbaAgentJob -ModuleName "dbatools"
            $jobs = Get-JobList -SqlInstance $server
            $output = $jobs
        }

        if ($Category) {
            Write-Message -Level Verbose -Message "Finding job/s that have the specified category defined" -FunctionName Find-DbaAgentJob -ModuleName "dbatools"
            $output = $jobs | Where-Object { $Category -contains $_.Category }
        }

        if ($IsFailed) {
            Write-Message -Level Verbose -Message "Checking for failed jobs." -FunctionName Find-DbaAgentJob -ModuleName "dbatools"
            $output = $jobs | Where-Object LastRunOutcome -eq "Failed"
        }

        if ($LastUsed) {
            $DaysBack = $LastUsed * -1
            $SinceDate = (Get-Date).AddDays($DaysBack)
            Write-Message -Level Verbose -Message "Finding job/s not ran in last $LastUsed days" -FunctionName Find-DbaAgentJob -ModuleName "dbatools"
            $output = $jobs | Where-Object { $_.LastRunDate -le $SinceDate }
        }

        if ($IsDisabled) {
            Write-Message -Level Verbose -Message "Finding job/s that are disabled" -FunctionName Find-DbaAgentJob -ModuleName "dbatools"
            $output = $jobs | Where-Object IsEnabled -eq $false
        }

        if ($IsNotScheduled) {
            Write-Message -Level Verbose -Message "Finding job/s that have no schedule defined" -FunctionName Find-DbaAgentJob -ModuleName "dbatools"
            $output = $jobs | Where-Object HasSchedule -eq $false
        }
        if ($IsNoEmailNotification) {
            Write-Message -Level Verbose -Message "Finding job/s that have no email operator defined" -FunctionName Find-DbaAgentJob -ModuleName "dbatools"
            $output = $jobs | Where-Object { [string]::IsNullOrEmpty($_.OperatorToEmail) -eq $true }
        }

        if ($Owner) {
            Write-Message -Level Verbose -Message "Finding job/s with owner critera" -FunctionName Find-DbaAgentJob -ModuleName "dbatools"
            if ($Owner -match "-") {
                $OwnerMatch = $Owner -replace "-", ""
                Write-Message -Level Verbose -Message "Checking for jobs that NOT owned by: $OwnerMatch" -FunctionName Find-DbaAgentJob -ModuleName "dbatools"
                $output = $jobs | Where-Object { $OwnerMatch -notcontains $_.OwnerLoginName }
            } else {
                Write-Message -Level Verbose -Message "Checking for jobs that are owned by: $owner" -FunctionName Find-DbaAgentJob -ModuleName "dbatools"
                $output = $jobs | Where-Object { $Owner -contains $_.OwnerLoginName }
            }
        }

        if ($ExcludeJobName) {
            Write-Message -Level Verbose -Message "Excluding job/s based on Exclude" -FunctionName Find-DbaAgentJob -ModuleName "dbatools"
            $output = $output | Where-Object { $ExcludeJobName -notcontains $_.Name }
        }

        if ($Since) {
            #$Since = $Since.ToString("yyyy-MM-dd HH:mm:ss")
            Write-Message -Level Verbose -Message "Getting only jobs whose LastRunDate is greater than or equal to $since" -FunctionName Find-DbaAgentJob -ModuleName "dbatools"
            $output = $output | Where-Object { $_.LastRunDate -ge $since }
        }

        $jobs = $output | Select-Object -Unique

        foreach ($job in $jobs) {
            Add-Member -Force -InputObject $job -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
            Add-Member -Force -InputObject $job -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
            Add-Member -Force -InputObject $job -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
            Add-Member -Force -InputObject $job -MemberType NoteProperty -Name JobName -value $job.Name

            Select-DefaultView -InputObject $job -Property ComputerName, InstanceName, SqlInstance, Name, Category, OwnerLoginName, CurrentRunStatus, CurrentRunRetryAttempt, 'IsEnabled as Enabled', LastRunDate, LastRunOutcome, DateCreated, HasSchedule, OperatorToEmail, 'DateCreated as CreateDate'
        }
    }
} $SqlInstance $SqlCredential $JobName $ExcludeJobName $StepName $LastUsed $IsDisabled $IsFailed $IsNotScheduled $IsNoEmailNotification $Category $Owner $Since $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

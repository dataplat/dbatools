#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoAgentJob = Microsoft.SqlServer.Management.Smo.Agent.Job;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets the owner of SQL Server Agent jobs.
/// </summary>
/// <remarks>
/// The instance connection, the job collection/filtering, the owner resolution and validation, the
/// Alter, and the result-object shaping all run the original dbatools PowerShell body inside the dbatools
/// module scope rather than being reimplemented in C#, so the engine decides the observable details.
///
/// Both SqlInstance and InputObject bind from the pipeline (no parameter sets). The body gathers each
/// instance's jobs into $InputObject and then updates every job in $InputObject; neither the gathered
/// collection nor the pipeline binding carries across records (a VFP param is rebound each record), so a
/// single per-record hop reproduces both.
///
/// The $status and $notes locals ARE pipeline-spanning in the source's shared process scope: the catch
/// path (Alter throws) leaves them unset, so a job that failed to alter reports the previous job's
/// status/notes - and across records that stale value carries from one record's last job to the next
/// record's first. A per-record hop scope would reset them, so they are carried across records via a
/// sentinel (seeded from C# fields at the top of the hop, re-emitted at the end).
///
/// Output streams: each job's result is emitted before a later Alter may throw under -EnableException.
/// This cmdlet supplies the real ShouldProcess runtime (ConfirmImpact defaults to Medium, no -Force).
/// Surface pinned by migration/baselines/Set-DbaAgentJobOwner.json.
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaAgentJobOwner", SupportsShouldProcess = true)]
public sealed class SetDbaAgentJobOwnerCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only update these named jobs.</summary>
    [Parameter(Position = 2)]
    [Alias("Jobs")]
    public object[]? Job { get; set; }

    /// <summary>Update all jobs except these named ones.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeJob { get; set; }

    /// <summary>Agent job objects piped in from Get-DbaAgentJob.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public SmoAgentJob[]? InputObject { get; set; }

    /// <summary>The login to set as the job owner (defaults to the sa login).</summary>
    [Parameter(Position = 5)]
    [Alias("TargetLogin")]
    public string? Login { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which the
    // inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    // $status/$notes carried across records: the catch path leaves them unset, and the source's shared
    // process scope keeps the previous value; a per-record hop scope would reset them. $instance is the
    // first loop's variable, read as the ShouldProcess target in the second loop; an InputObject-only
    // record (SqlInstance empty) never re-enters the first loop, so in the shared scope it keeps the prior
    // record's $instance - carried the same way.
    private string? _status;
    private string? _notes;
    private object? _instance;

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__setDbaAgentJobOwnerState"))
            {
                if (sentinel["__setDbaAgentJobOwnerState"] is Hashtable state)
                {
                    _status = state["Status"] as string;
                    _notes = state["Notes"] as string;
                    _instance = state["Instance"];
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
            SqlInstance, SqlCredential, Job, ExcludeJob, InputObject, Login, EnableException.ToBool(),
            _status, _notes, _instance, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from $PSCmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess and
    // -FunctionName Set-DbaAgentJobOwner on the direct Stop-Function/Write-Message sites. $status/$notes
    // are seeded from the carried values at the top and re-emitted in a sentinel at the end so the source's
    // cross-record leak of those locals is reproduced.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Job, $ExcludeJob, $InputObject, $Login, $EnableException, $__carriedStatus, $__carriedNotes, $__carriedInstance, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Job, [object[]]$ExcludeJob, [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject, [string]$Login, $EnableException, $__carriedStatus, $__carriedNotes, $__carriedInstance, $__realCmdlet)
    # Seed the carried cross-record state of $status/$notes/$instance (source keeps them in the shared process scope).
    $status = $__carriedStatus
    $notes = $__carriedNotes
    $instance = $__carriedInstance
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaAgentJobOwner
        }

        #Get job list. If value for -Job is passed, massage to make it a string array.
        #Otherwise, use all jobs on the instance where owner not equal to -TargetLogin
        Write-Message -Level Verbose -Message "Gathering jobs to update." -FunctionName Set-DbaAgentJobOwner -ModuleName "dbatools"

        if ($Job) {
            $jobcollection = $server.JobServer.Jobs | Where-Object { $Job -contains $_.Name }
        } else {
            $jobcollection = $server.JobServer.Jobs | Where-Object JobType -eq Local
        }

        if ($ExcludeJob) {
            $jobcollection = $jobcollection | Where-Object { $ExcludeJob -notcontains $_.Name }
        }

        $InputObject += $jobcollection
    }

    Write-Message -Level Verbose -Message "Updating $($InputObject.Count) job(s)." -FunctionName Set-DbaAgentJobOwner -ModuleName "dbatools"
    foreach ($agentJob in $InputObject) {
        $jobname = $agentJob.Name
        $server = $agentJob.Parent.Parent

        if (-not $Login) {
            # dynamic sa name for orgs who have changed their sa name
            $newLogin = ($server.logins | Where-Object { $_.id -eq 1 }).Name
        } else {
            $newLogin = $Login
        }

        #Validate login
        if ($agentJob.OwnerLoginName -eq $newLogin) {
            $status = 'Skipped'
            $notes = "Owner already set"
        } else {
            if (($server.Logins.Name) -notcontains $newLogin) {
                $status = 'Failed'
                $notes = "Login $newLogin not valid"
            } else {
                if ($server.logins[$newLogin].LoginType -eq 'WindowsGroup') {
                    $status = 'Failed'
                    $notes = "$newLogin is a Windows Group and can not be a job owner."
                } else {
                    if ($__realCmdlet.ShouldProcess($instance, "Setting job owner for $jobname to $newLogin")) {
                        try {
                            Write-Message -Level Verbose -Message "Setting job owner for $jobname to $newLogin on $instance." -FunctionName Set-DbaAgentJobOwner -ModuleName "dbatools"
                            #Set job owner to $TargetLogin (default 'sa')
                            $agentJob.OwnerLoginName = $newLogin
                            $agentJob.Alter()
                            $status = 'Successful'
                            $notes = ''
                        } catch {
                            Stop-Function -Message "Issue setting job owner on $jobName." -Target $jobName -InnerErrorRecord $_ -Category InvalidOperation -FunctionName Set-DbaAgentJobOwner
                        }
                    }
                }
            }
        }
        Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
        Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
        Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
        Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name Status -value $status
        Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name Notes -value $notes
        Select-DefaultView -InputObject $agentJob -Property ComputerName, InstanceName, SqlInstance, Name, Category, OwnerLoginName, Status, Notes
    }

    @{ __setDbaAgentJobOwnerState = @{ Status = $status; Notes = $notes; Instance = $instance } }
} $SqlInstance $SqlCredential $Job $ExcludeJob $InputObject $Login $EnableException $__carriedStatus $__carriedNotes $__carriedInstance $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}

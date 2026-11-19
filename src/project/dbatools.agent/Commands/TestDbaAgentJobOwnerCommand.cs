#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests whether SQL Server Agent jobs are owned by the target login.
/// </summary>
/// <remarks>
/// The instance connection, the login validation, the job collection/filtering, the per-job row
/// construction, and the result output all run the original dbatools PowerShell body inside the dbatools
/// module scope rather than being reimplemented in C#, so the engine decides the observable details.
///
/// The function accumulates its result rows across the whole pipeline: begin seeds $return = @(), process
/// appends a row per job and derives $results (the full $return, or its OwnerMatch = $false subset unless
/// -Job), and end emits $results. Three locals span the pipeline in the source's shared process scope and
/// are reset by a per-record hop scope, so they are carried record-to-record via a sentinel: $return (the
/// cumulative rows), $results (the last derived subset), and $Login (reassigned to the dynamic sa login;
/// with -Login sa across servers whose sa was renamed, the source keeps the previous server's resolved
/// name). The "-Login was bound" test also cannot use the hop's own $PSBoundParameters, so it is a carried
/// flag.
///
/// The body is dot-sourced so the validation's early "return" (single invalid login, or a Windows-group
/// login) exits only the block and the state sentinel is still emitted, keeping the carry consistent.
/// Read-only: no ShouldProcess, no mutation. Surface pinned by migration/baselines/Test-DbaAgentJobOwner.json.
/// </remarks>
[Cmdlet(VerbsDiagnostic.Test, "DbaAgentJobOwner")]
[OutputType(typeof(object[]))]
public sealed class TestDbaAgentJobOwnerCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only check these named jobs.</summary>
    [Parameter(Position = 2)]
    [Alias("Jobs")]
    public object[]? Job { get; set; }

    /// <summary>Check all jobs except these named ones.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeJob { get; set; }

    /// <summary>The login expected to own the jobs (defaults to the sa login).</summary>
    [Parameter(Position = 4)]
    [Alias("TargetLogin")]
    public string? Login { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - bare in the source (all sets), inherited match.

    // Cross-record carries (the source keeps these in its shared process scope): the cumulative $return
    // rows, the last-derived $results subset, and the reassigned $Login. _loginSeeded distinguishes the
    // first record (which uses the bound Login) from later records (which use the carried value).
    private object? _return;
    private object? _results;
    private string? _login;
    private bool _loginSeeded;

    protected override void BeginProcessing()
    {
        _return = Array.Empty<object>();
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        object? carriedLogin = _loginSeeded ? _login : Login;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__testDbaAgentJobOwnerState"))
            {
                if (sentinel["__testDbaAgentJobOwnerState"] is Hashtable state)
                {
                    _return = state["Return"];
                    _results = state["Results"];
                    _login = state["Login"] as string;
                    _loginSeeded = true;
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
            SqlInstance, SqlCredential, Job, ExcludeJob, EnableException.ToBool(),
            MyInvocation.BoundParameters.ContainsKey("Login"), _return, _results, carriedLogin,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, EndScript,
            _results, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
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

    // PS: the process block VERBATIM apart from $PSBoundParameters.ContainsKey('Login') -> the carried
    // $__boundLogin flag and -FunctionName Test-DbaAgentJobOwner on the direct Stop-Function/Write-Message
    // sites. $return/$results/$Login are seeded from the carried state at the top and re-emitted in a
    // sentinel; the body is dot-sourced so the validation's early return still reaches the sentinel.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Job, $ExcludeJob, $EnableException, $__boundLogin, $__carriedReturn, $__carriedResults, $__carriedLogin, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Job, [object[]]$ExcludeJob, $EnableException, $__boundLogin, $__carriedReturn, $__carriedResults, $__carriedLogin)
    # Seed the carried cross-record state (source keeps $return/$results/$Login in the shared process scope).
    $return = $__carriedReturn
    $results = $__carriedResults
    $Login = $__carriedLogin
    . {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaAgentJobOwner
            }

            #Validate login
            if ($Login -and ($server.Logins.Name) -notcontains $Login) {
                if ($SqlInstance.count -eq 1) {
                    Stop-Function -Message "Invalid login: $Login." -FunctionName Test-DbaAgentJobOwner
                    return
                } else {
                    Write-Message -Level Warning -Message "$Login is not a valid login on $instance. Moving on." -FunctionName Test-DbaAgentJobOwner -ModuleName "dbatools"
                    continue
                }
            }
            if ($Login -and $server.Logins[$Login].LoginType -eq 'WindowsGroup') {
                Stop-Function -Message "$Login is a Windows Group and can not be a job owner." -FunctionName Test-DbaAgentJobOwner
                return
            }

            #Sets the Default Login to sa if the Login Paramater is not set.
            if (!($__boundLogin)) {
                $Login = "sa"
            }
            #sql2000 id property is empty -force target login to 'sa' login
            if ($Login -and ( ($server.VersionMajor -lt 9) -and ([string]::IsNullOrEmpty($Login)) )) {
                $Login = "sa"
            }
            # dynamic sa name for orgs who have changed their sa name
            if ($Login -eq "sa") {
                $Login = ($server.Logins | Where-Object { $_.id -eq 1 }).Name
            }

            #Get database list. If value for -Job is passed, massage to make it a string array.
            #Otherwise, use all jobs on the instance where owner not equal to -TargetLogin
            Write-Message -Level Verbose -Message "Gathering jobs to check." -FunctionName Test-DbaAgentJobOwner -ModuleName "dbatools"
            if ($Job) {
                $jobCollection = $server.JobServer.Jobs | Where-Object { $Job -contains $_.Name }
            } elseif ($ExcludeJob) {
                $jobCollection = $server.JobServer.Jobs | Where-Object { $ExcludeJob -notcontains $_.Name }
            } else {
                $jobCollection = $server.JobServer.Jobs
            }

            #for each database, create custom object for return set.
            foreach ($j in $jobCollection) {
                Write-Message -Level Verbose -Message "Checking $j" -FunctionName Test-DbaAgentJobOwner -ModuleName "dbatools"
                $row = [ordered]@{
                    Server       = $server.Name
                    Job          = $j.Name
                    JobType      = if ($j.CategoryID -eq 1) { "Remote" } else { $j.JobType }
                    CurrentOwner = $j.OwnerLoginName
                    TargetOwner  = $Login
                    OwnerMatch   = if ($j.CategoryID -eq 1) { $true } else { $j.OwnerLoginName -eq $Login }

                }
                #add each custom object to the return array
                $return += New-Object PSObject -Property $row
            }
            if ($Job) {
                $results = $return
            } else {
                $results = $return | Where-Object { $_.OwnerMatch -eq $False }
            }
        }
    }

    @{ __testDbaAgentJobOwnerState = @{ Return = $return; Results = $results; Login = $Login } }
} $SqlInstance $SqlCredential $Job $ExcludeJob $EnableException $__boundLogin $__carriedReturn $__carriedResults $__carriedLogin @__commonParameters 3>&1 2>&1
""";

    // PS: the end block. Emits $results (the carried last-derived subset) through Select-DefaultView.
    private const string EndScript = """
param($results, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($results)
    #return results
    Select-DefaultView -InputObject $results -Property Server, Job, JobType, CurrentOwner, TargetOwner, OwnerMatch
} $results @__commonParameters 3>&1 2>&1
""";
}

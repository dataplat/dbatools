#nullable enable

using System;
using System.Collections;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoAgentCompletionResult = Microsoft.SqlServer.Management.Smo.Agent.CompletionResult;
using SmoAgentJob = Microsoft.SqlServer.Management.Smo.Agent.Job;
using SmoAgentJobHistoryFilter = Microsoft.SqlServer.Management.Smo.Agent.JobHistoryFilter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves and decorates SQL Agent job execution history. The token-expansion and output-shaping
/// workflow remains a module-scoped PowerShell compatibility hop; the compiled cmdlet preserves
/// the advanced function's begin/process lifetime and typed pipeline surface. Surface pinned by
/// migration/baselines/Get-DbaAgentJobHistory.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaAgentJobHistory", DefaultParameterSetName = "Default")]
public sealed class GetDbaAgentJobHistoryCommand : DbaBaseCmdlet
{
    /// <summary>Target SQL Server instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "Server")]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Job names whose history should be returned.</summary>
    [Parameter]
    public object[]? Job { get; set; }

    /// <summary>Job names whose history should be excluded.</summary>
    [Parameter]
    public object[]? ExcludeJob { get; set; }

    /// <summary>Earliest history timestamp to return.</summary>
    [Parameter]
    [PsDateTimeCast]
    public DateTime StartDate { get; set; } = new(1900, 1, 1);

    /// <summary>Latest history timestamp to return.</summary>
    [Parameter]
    [PsDateTimeCast]
    public DateTime EndDate { get; set; } = DateTime.Now;

    /// <summary>Completion result to return.</summary>
    [Parameter]
    [PsCompletionResultCast]
    [ValidateSet("Failed", "Succeeded", "Retry", "Cancelled", "InProgress", "Unknown")]
    public SmoAgentCompletionResult OutcomeType { get; set; }

    /// <summary>Return job-level outcomes only.</summary>
    [Parameter]
    public SwitchParameter ExcludeJobSteps { get; set; }

    /// <summary>Resolve SQL Agent output-file tokens.</summary>
    [Parameter]
    public SwitchParameter WithOutputFile { get; set; }

    /// <summary>SQL Agent job supplied directly or through the pipeline.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "Collection")]
    public SmoAgentJob? JobCollection { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private SmoAgentJobHistoryFilter? _filter;
    private bool _beginInterrupted;

    protected override void BeginProcessing()
    {
        bool completed = false;
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            StartDate, EndDate, OutcomeType, ExcludeJobSteps.ToBool(), WithOutputFile.ToBool(),
            EnableException.ToBool(), TestBound("OutcomeType"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item?.BaseObject is SmoAgentJobHistoryFilter filter)
            {
                _filter = filter;
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__GetDbaAgentJobHistoryBeginComplete"]?.Value))
            {
                completed = true;
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }
        _beginInterrupted = !completed || _filter is null || (ExcludeJobSteps && WithOutputFile);
    }

    protected override void ProcessRecord()
    {
        if (_beginInterrupted || Interrupted)
            return;

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
            _filter, SqlInstance, SqlCredential, Job, ExcludeJob,
            ExcludeJobSteps.ToBool(), WithOutputFile.ToBool(), JobCollection,
            EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string BeginScript = """
param($StartDate, $EndDate, $OutcomeType, $ExcludeJobSteps, $WithOutputFile, $EnableException, $__boundOutcomeType, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([datetime]$StartDate, [datetime]$EndDate, [Microsoft.SqlServer.Management.Smo.Agent.CompletionResult]$OutcomeType, $ExcludeJobSteps, $WithOutputFile, $EnableException, $__boundOutcomeType)

    $filter = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobHistoryFilter
    $filter.StartRunDate = $StartDate
    $filter.EndRunDate = $EndDate
    if ($__boundOutcomeType) {
        $filter.OutcomeTypes = $OutcomeType
    }
    if ($ExcludeJobSteps -and $WithOutputFile) {
        Stop-Function -Message "You can't use -ExcludeJobSteps and -WithOutputFile together" -FunctionName Get-DbaAgentJobHistory
    }
    $filter
    [pscustomobject]@{ __GetDbaAgentJobHistoryBeginComplete = $true }
} $StartDate $EndDate $OutcomeType $ExcludeJobSteps $WithOutputFile $EnableException $__boundOutcomeType @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = """
param($Filter, $SqlInstance, $SqlCredential, $Job, $ExcludeJob, $ExcludeJobSteps, $WithOutputFile, $JobCollection, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Microsoft.SqlServer.Management.Smo.Agent.JobHistoryFilter]$Filter, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Job, [object[]]$ExcludeJob, $ExcludeJobSteps, $WithOutputFile, [Microsoft.SqlServer.Management.Smo.Agent.Job]$JobCollection, $EnableException)

    function Get-JobHistory {
        [CmdletBinding()]
        param($Server, $Job, [switch]$WithOutputFile)

        $tokenrex = [regex]'\$\((?<method>[^()]+)\((?<tok>[^)]+)\)\)|\$\((?<tok>[^)]+)\)'
        $propmap = @{
            'INST' = $Server.ServiceName
            'MACH' = $Server.ComputerName
            'SQLDIR' = $Server.InstallDataDirectory
            'SQLLOGDIR' = $Server.ErrorLogPath
            'SRVR' = $Server.DomainInstanceName
        }
        $squote_rex = [regex]"(?<!')'(?!')"
        $dquote_rex = [regex]'(?<!")"(?!")'
        $rbrack_rex = [regex]'(?<!])](?!])'

        function Resolve-TokenEscape($method, $value) {
            if (!$method) { return $value }
            $value = switch ($method) {
                'ESCAPE_SQUOTE' { $squote_rex.Replace($value, "''") }
                'ESCAPE_DQUOTE' { $dquote_rex.Replace($value, '""') }
                'ESCAPE_RBRACKET' { $rbrack_rex.Replace($value, ']]') }
                'ESCAPE_NONE' { $value }
                default { $value }
            }
            return $value
        }

        function Resolve-JobToken($exec, $outfile, $outcome) {
            $n = $tokenrex.Matches($outfile)
            foreach ($x in $n) {
                $tok = $x.Groups['tok'].Value
                $EscMethod = $x.Groups['method'].Value
                if ($propmap.containskey($tok)) {
                    $repl = Resolve-TokenEscape -method $EscMethod -value $propmap[$tok]
                    $outfile = $outfile.Replace($x.Value, $repl)
                } elseif ($tok -eq 'STEPID') {
                    $repl = Resolve-TokenEscape -method $EscMethod -value $exec.StepID
                    $outfile = $outfile.Replace($x.Value, $repl)
                } elseif ($tok -eq 'JOBID') {
                    $repl = @('0x') + @($exec.JobID.ToByteArray() | ForEach-Object -Process { $_.ToString('X2') }) -join ''
                    $repl = Resolve-TokenEscape -method $EscMethod -value $repl
                    $outfile = $outfile.Replace($x.Value, $repl)
                } elseif ($tok -eq 'STRTDT') {
                    $repl = Resolve-TokenEscape -method $EscMethod -value $outcome.RunDate.toString('yyyyMMdd')
                    $outfile = $outfile.Replace($x.Value, $repl)
                } elseif ($tok -eq 'STRTTM') {
                    $repl = Resolve-TokenEscape -method $EscMethod -value ([int]$outcome.RunDate.toString('HHmmss')).toString()
                    $outfile = $outfile.Replace($x.Value, $repl)
                } elseif ($tok -eq 'DATE') {
                    $repl = Resolve-TokenEscape -method $EscMethod -value $exec.RunDate.toString('yyyyMMdd')
                    $outfile = $outfile.Replace($x.Value, $repl)
                } elseif ($tok -eq 'TIME') {
                    $repl = Resolve-TokenEscape -method $EscMethod -value ([int]$exec.RunDate.toString('HHmmss')).toString()
                    $outfile = $outfile.Replace($x.Value, $repl)
                }
            }
            return $outfile
        }

        try {
            Write-Message -Message "Attempting to get job history from $instance" -Level Verbose
            if ($Job) {
                foreach ($currentjob in $Job) {
                    $Filter.JobName = $currentjob
                    $executions += $Server.JobServer.EnumJobHistory($Filter)
                }
            } else {
                $executions = $Server.JobServer.EnumJobHistory($Filter)
            }
            if ($ExcludeJobSteps) {
                $executions = $executions | Where-Object { $_.StepID -eq 0 }
            }
            if ($WithOutputFile) {
                $outmap = @{}
                $outfiles = Get-DbaAgentJobOutputFile -SqlInstance $Server -SqlCredential $SqlCredential -Job $Job
                foreach ($out in $outfiles) {
                    if (!$outmap.ContainsKey($out.Job)) { $outmap[$out.Job] = @{} }
                    $outmap[$out.Job][$out.StepId] = $out.OutputFileName
                }
            }
            $outcome = [PSCustomObject]@{}
            foreach ($execution in $executions) {
                $status = switch ($execution.RunStatus) {
                    0 { "Failed" }
                    1 { "Succeeded" }
                    2 { "Retry" }
                    3 { "Canceled" }
                }
                Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name ComputerName -value $Server.ComputerName
                Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name InstanceName -value $Server.ServiceName
                Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name SqlInstance -value $Server.DomainInstanceName
                $DurationInSeconds = ($execution.RunDuration % 100) + [math]::floor(($execution.RunDuration % 10000) / 100) * 60 + [math]::floor(($execution.RunDuration % 1000000) / 10000) * 60 * 60
                Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name StartDate -value ([dbadatetime]$execution.RunDate)
                Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name EndDate -value ([dbadatetime]$execution.RunDate.AddSeconds($DurationInSeconds))
                Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name Duration -value ([prettytimespan](New-TimeSpan -Seconds $DurationInSeconds))
                Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name Status -value $status
                if ($WithOutputFile) {
                    if ($execution.StepID -eq 0) { $outcome = $execution }
                    try {
                        $outname = $outmap[$execution.JobName][$execution.StepID]
                        $outname = Resolve-JobToken -exec $execution -outcome $outcome -outfile $outname
                        $outremote = Join-AdminUNC $Server.ComputerName $outname
                    } catch {
                        $outname = ''
                        $outremote = ''
                    }
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name OutputFileName -value $outname
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name RemoteOutputFileName -value $outremote
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name TypeName -value AgentJobHistory
                    Select-DefaultView -InputObject $execution -Property ComputerName, InstanceName, SqlInstance, 'JobName as Job', StepName, RunDate, StartDate, EndDate, Duration, Status, OperatorEmailed, Message, OutputFileName, RemoteOutputFileName -TypeName AgentJobHistory
                } else {
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name TypeName -value AgentJobHistory
                    Select-DefaultView -InputObject $execution -Property ComputerName, InstanceName, SqlInstance, 'JobName as Job', StepName, RunDate, StartDate, EndDate, Duration, Status, OperatorEmailed, Message -TypeName AgentJobHistory
                }
            }
        } catch {
            Stop-Function -Message "Could not get Agent Job History from $instance" -Target $instance -Continue
        }
    }

    if (Test-FunctionInterrupt) { return }
    if ($JobCollection) {
        foreach ($currentjob in $JobCollection) {
            Get-JobHistory -Server $currentjob.Parent.Parent -Job $currentjob.Name -WithOutputFile:$WithOutputFile
        }
    }
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Get-DbaAgentJobHistory
        }
        if ($ExcludeJob) {
            $jobs = $server.JobServer.Jobs.Name | Where-Object { $_ -notin $ExcludeJob }
            foreach ($currentjob in $jobs) {
                Get-JobHistory -Server $server -Job $currentjob -WithOutputFile:$WithOutputFile
            }
        } else {
            Get-JobHistory -Server $server -Job $Job -WithOutputFile:$WithOutputFile
        }
    }
} $Filter $SqlInstance $SqlCredential $Job $ExcludeJob $ExcludeJobSteps $WithOutputFile $JobCollection $EnableException @__commonParameters 3>&1 2>&1
""";
}

/// <summary>Reproduces the advanced-function enum cast before ValidateSet executes.</summary>
internal sealed class PsCompletionResultCastAttribute : ArgumentTransformationAttribute
{
    public override object? Transform(EngineIntrinsics engineIntrinsics, object? inputData)
    {
        try
        {
            return LanguagePrimitives.ConvertTo(inputData, typeof(SmoAgentCompletionResult), CultureInfo.InvariantCulture);
        }
        catch (PSInvalidCastException ex)
        {
            throw new ArgumentTransformationMetadataException(ex.Message, ex);
        }
    }
}

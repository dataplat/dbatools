#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Installs or updates the SqlWatch monitoring solution (via DACPAC publish) on a target instance. The
/// local-cache refresh, DACPAC profile creation/publish, and ShouldProcess flow remain a module-scoped
/// PowerShell compatibility hop; this cmdlet supplies the real ShouldProcess runtime and preserves the
/// advanced function's begin/process lifetime. Surface pinned by migration/baselines/Install-DbaSqlWatch.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Install, "DbaSqlWatch", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class InstallDbaSqlWatchCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database to install SqlWatch into.</summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    public string Database { get; set; } = "SQLWATCH";

    /// <summary>Install from a local zip/folder instead of downloading.</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    public string? LocalFile { get; set; }

    /// <summary>Install the pre-release build of SqlWatch.</summary>
    [Parameter]
    public SwitchParameter PreRelease { get; set; }

    /// <summary>Force a refresh of the local cached copy of the software.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _localCachedCopy;
    private bool _beginInterrupted;
    // $stepCounter is a function-scoped progress accumulator: begin sets it to 0, process increments it
    // (2 per instance) and it carries ACROSS pipeline records in the function. A per-record hop resets it,
    // so we carry it (reproduce-not-sanitize) to keep the progress step numbers identical. Starts at the
    // begin value (0). Note: $server needs NO carrier here - its connect is inside the gate that wraps the
    // whole per-instance body, so every read is same-gate and Continue-dominated.
    private object? _stepCounter;
    // The process emits a controlled status object; a per-invocation GUID token keeps the carrier sentinel
    // from ever colliding with pipeline output (carrier-note guidance).
    private readonly string _processToken = Guid.NewGuid().ToString("N");

    protected override void BeginProcessing()
    {
        bool completed = false;
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Force.ToBool(), LocalFile, PreRelease.ToBool(), Database, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__InstallSqlWatchBeginComplete"]?.Value))
            {
                _localCachedCopy = UnwrapHopValue(item.Properties["LocalCachedCopy"]?.Value);
                _stepCounter = UnwrapHopValue(item.Properties["StepCounter"]?.Value);
                _beginInterrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
                completed = true;
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }
        if (!completed)
            _beginInterrupted = true;
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
            else if (item is not null && string.Equals(
                item.Properties["__InstallSqlWatchProcessComplete"]?.Value as string, _processToken, StringComparison.Ordinal))
            {
                _stepCounter = UnwrapHopValue(item.Properties["StepCounter"]?.Value);
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, _localCachedCopy, _stepCounter, Force.ToBool(),
            EnableException.ToBool(), this, _processToken,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // Carried hop state arrives PSObject-wrapped. A PSCustomObject carries its content on the
    // wrapper rather than the BaseObject, so unwrapping one would discard it - keep it wrapped.
    private static object? UnwrapHopValue(object? value)
    {
        if (value is PSObject wrapper && wrapper.BaseObject is not PSCustomObject)
            return wrapper.BaseObject;
        return value;
    }

    private const string BeginScript = """
param($Force, $LocalFile, $PreRelease, $Database, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param($Force, [string]$LocalFile, $PreRelease, [string]$Database, $EnableException, $__realCmdlet)

    if ($Force) { $ConfirmPreference = 'none' }

    # Do we need a new local cached version of the software?
    $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
    if ($PreRelease) {
        $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child "SQLWATCH-prerelease"
        $branch = 'prerelease'
    } else {
        $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child "SQLWATCH"
        $branch = 'release'
    }
    if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
        if ($__realCmdlet.ShouldProcess('SQLWATCH', 'Update local cached copy of the software')) {
            try {
                Save-DbaCommunitySoftware -Software SQLWATCH -Branch $branch -LocalFile $LocalFile -EnableException
            } catch {
                Stop-Function -Message 'Failed to update local cached copy' -ErrorRecord $_ -FunctionName Install-DbaSqlWatch
            }
        }
    }

    $stepCounter = 0

    if ($Database -eq 'tempdb') {
        Stop-Function -Message "Installation to tempdb not supported" -FunctionName Install-DbaSqlWatch
        return
    }

    [pscustomobject]@{ __InstallSqlWatchBeginComplete = $true; LocalCachedCopy = $localCachedCopy; StepCounter = $stepCounter; Interrupted = [bool](Test-FunctionInterrupt) }
} $Force $LocalFile $PreRelease $Database $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $localCachedCopy, $stepCounter, $Force, $EnableException, $__realCmdlet, $__processToken, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string]$Database, $localCachedCopy, $stepCounter, $Force, $EnableException, $__realCmdlet, $__processToken)

    # -Force sets function-scoped $ConfirmPreference='none' in the SOURCE begin, persisting across process
    # records; separate hops don't share that scope, so re-establish it here (T26, carried via $Force).
    if ($Force) { $ConfirmPreference = 'none' }
    # W2-208/T20 named-wrapper shim: Write-ProgressHelper reads (Get-PSCallStack)[1].Command and its
    # switch($caller) has an 'Install-DbaSqlWatch' case for bespoke progress text; through a bare hop
    # scriptblock the caller is <ScriptBlock>, missing the case (custom text lost). A dot-sourced function
    # literally named Install-DbaSqlWatch restores the caller frame - scope + cross-record $stepCounter
    # are unchanged by the dot-source.
    function Install-DbaSqlWatch {
    if (Test-FunctionInterrupt) {
        return
    }

    if ($PSEdition -eq 'Core') {
        Stop-Function -Message "PowerShell Core is not supported, please use Windows PowerShell." -FunctionName Install-DbaSqlWatch
        return
    }
    $totalSteps = $stepCounter + $SqlInstance.Count * 2
    foreach ($instance in $SqlInstance) {
        if ($__realCmdlet.ShouldProcess($instance, "Installing SqlWatch on $Database")) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Install-DbaSqlWatch
            }

            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Starting installing/updating SqlWatch in $database on $instance" -TotalSteps $totalSteps


            try {
                # create a publish profile and publish DACPAC
                $DacPacPath = Get-ChildItem -Filter "SqlWatch.dacpac" -Path $localCachedCopy -Recurse | Select-Object -ExpandProperty FullName
                $PublishOptions = @{
                    RegisterDataTierApplication = $true
                }

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Publishing SqlWatch dacpac to $database on $instance" -TotalSteps $totalSteps
                $DacProfile = New-DbaDacProfile -SqlInstance $server -Database $Database -Path $localCachedCopy -PublishOptions $PublishOptions -EnableException | Select-Object -ExpandProperty FileName
                $PublishResults = Publish-DbaDacPackage -SqlInstance $server -Database $Database -Path $DacPacPath -PublishXml $DacProfile -EnableException

                # parse results
                $parens = Select-String -InputObject $PublishResults.Result -Pattern "\(([^\)]+)\)" -AllMatches
                if ($parens.matches) {
                    $ExtractedResult = $parens.matches | Select-Object -Last 1
                }

                [PSCustomObject]@{
                    ComputerName  = $PublishResults.ComputerName
                    InstanceName  = $PublishResults.InstanceName
                    SqlInstance   = $PublishResults.SqlInstance
                    Database      = $PublishResults.Database
                    Status        = $ExtractedResult
                    DashboardPath = $localCachedCopy + '\SqlWatch.Dashboard'
                }
            } catch {
                Stop-Function -Message "DACPAC failed to publish to $database on $instance." -ErrorRecord $_ -Target $instance -Continue -FunctionName Install-DbaSqlWatch
            } finally {
                Remove-Item -Path $DacProfile -ErrorAction SilentlyContinue
            }

            Write-Message -Level Verbose -Message "Finished installing/updating SqlWatch in $database on $instance." -FunctionName Install-DbaSqlWatch -ModuleName "dbatools"
        }
    }
    }
    . Install-DbaSqlWatch
    [pscustomobject]@{ __InstallSqlWatchProcessComplete = $__processToken; StepCounter = $stepCounter }
} $SqlInstance $SqlCredential $Database $localCachedCopy $stepCounter $Force $EnableException $__realCmdlet $__processToken @__commonParameters 3>&1 2>&1
""";
}

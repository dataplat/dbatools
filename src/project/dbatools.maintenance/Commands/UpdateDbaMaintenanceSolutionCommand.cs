#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Updates the stored procedures of Ola Hallengren's Maintenance Solution (CommandExecute,
/// DatabaseBackup, DatabaseIntegrityCheck, IndexOptimize) to the latest version on instances where
/// it is already installed, leaving tables/jobs/config intact. The local-cache refresh, procedure
/// discovery, per-procedure Invoke-DbaQuery update, and ShouldProcess flow remain a module-scoped
/// PowerShell compatibility hop; this cmdlet supplies the real ShouldProcess runtime and preserves
/// the advanced function's begin/process lifetime. The begin block resolves the Solution ordering
/// and the local cache path (and optionally downloads) once; those values are read - never mutated -
/// by every process record, so they are carried begin-&gt;process with no per-record feedback.
/// Surface pinned by migration/baselines/Update-DbaMaintenanceSolution.json.
/// </summary>
[Cmdlet(VerbsData.Update, "DbaMaintenanceSolution", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class UpdateDbaMaintenanceSolutionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database containing the existing maintenance solution procedures.</summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    public string Database { get; set; } = "master";

    /// <summary>Which maintenance solution components to update.</summary>
    [Parameter(Position = 3)]
    [ValidateSet("All", "Backup", "IntegrityCheck", "IndexOptimize", "CommandExecute")]
    public string[] Solution { get; set; } = new[] { "All" };

    /// <summary>Path to a local zip file with the maintenance solution instead of downloading.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string? LocalFile { get; set; }

    /// <summary>Force a fresh download of the latest maintenance solution from GitHub.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _localCachedCopy;
    private object? _solution;
    private bool _beginInterrupted;

    protected override void BeginProcessing()
    {
        bool completed = false;
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Force.ToBool(), LocalFile, Solution, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__UpdateMaintSolBeginComplete"]?.Value))
            {
                _localCachedCopy = UnwrapHopValue(item.Properties["LocalCachedCopy"]?.Value);
                _solution = UnwrapHopValue(item.Properties["Solution"]?.Value);
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
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, _solution, _localCachedCopy, Force.ToBool(),
            EnableException.ToBool(), this,
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
param($Force, $LocalFile, $Solution, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param($Force, [string]$LocalFile, [string[]]$Solution, $EnableException, $__realCmdlet)

    if ($Force) { $ConfirmPreference = 'none' }

    if ($Solution -contains 'All') {
        $Solution = @('CommandExecute', 'Backup', 'IntegrityCheck', 'IndexOptimize');
    } elseif ($Solution -contains 'CommandExecute') {
        # Take care that CommandExecute is the first procedure to update
        $Solution = @('CommandExecute') + ($Solution | Where-Object { $_ -ne 'CommandExecute' })
    }

    # Do we need a new local cached version of the software?
    $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
    $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child 'sql-server-maintenance-solution-main'
    if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
        if ($__realCmdlet.ShouldProcess('MaintenanceSolution', 'Update local cached copy of the software')) {
            try {
                Save-DbaCommunitySoftware -Software MaintenanceSolution -LocalFile $LocalFile -EnableException
            } catch {
                Stop-Function -Message 'Failed to update local cached copy' -ErrorRecord $_ -FunctionName Update-DbaMaintenanceSolution
            }
        }
    }

    [pscustomobject]@{ __UpdateMaintSolBeginComplete = $true; LocalCachedCopy = $localCachedCopy; Solution = $Solution; Interrupted = [bool](Test-FunctionInterrupt) }
} $Force $LocalFile $Solution $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Solution, $localCachedCopy, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string]$Database, [string[]]$Solution, $localCachedCopy, $Force, $EnableException, $__realCmdlet)

    # -Force sets function-scoped $ConfirmPreference='none' in the SOURCE begin, persisting across process
    # records; separate hops don't share that scope, so re-establish it here (carried via $Force).
    if ($Force) { $ConfirmPreference = 'none' }

    if (Test-FunctionInterrupt) {
        return
    }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -NonPooledConnection
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Update-DbaMaintenanceSolution
        }

        $db = $server.Databases | Where-Object Name -eq $Database
        if ($null -eq $db) {
            Stop-Function -Message "Database $Database not found on $instance. Skipping." -Target $instance -Continue -FunctionName Update-DbaMaintenanceSolution
        }

        $installedProcedures = Get-DbaModule -SqlInstance $server -Database $Database | Where-Object Name -in 'CommandExecute', 'DatabaseBackup', 'DatabaseIntegrityCheck', 'IndexOptimize'

        foreach ($solutionName in $Solution) {
            if ($solutionName -in 'Backup', 'IntegrityCheck') {
                $procedureName = 'Database' + $solutionName
            } else {
                $procedureName = $solutionName
            }

            if ($__realCmdlet.ShouldProcess($instance, "Update $solutionName with script $procedureName.sql")) {
                $output = [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Solution     = $solutionName
                    Procedure    = $procedureName
                    IsUpdated    = $false
                    Results      = $null
                }

                if ($procedureName -notin $installedProcedures.Name) {
                    $output.Results = 'Procedure not installed'
                } else {
                    $file = Get-ChildItem -Path $localCachedCopy -Recurse -File "$procedureName.sql"
                    if ($null -eq $file) {
                        $output.Results = 'File not found'
                    } else {
                        Write-Message -Level Verbose -Message "Updating $procedureName from $($file.FullName)." -FunctionName Update-DbaMaintenanceSolution -ModuleName "dbatools"
                        try {
                            $null = Invoke-DbaQuery -SqlInstance $server -File $file
                            $output.IsUpdated = $true
                            $output.Results = 'Updated'
                        } catch {
                            $output.Results = $_
                        }
                    }
                }

                $output
            }
        }

        # Close non-pooled connection as this is not done automatically. If it is a reused Server SMO, connection will be opened again automatically on next request.
        $null = $server | Disconnect-DbaInstance
    }
} $SqlInstance $SqlCredential $Database $Solution $localCachedCopy $Force $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}

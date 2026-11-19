#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Installs Ola Hallengren's Maintenance Solution stored procedures and optional SQL Agent jobs. The
/// connectivity/internet detection and local-cache refresh (begin), and the per-instance install,
/// ReplaceExisting cleanup, job scheduling, job-step parameterization, and every ShouldProcess gate
/// (process) remain a module-scoped PowerShell compatibility hop; this cmdlet supplies the real
/// ShouldProcess runtime and preserves the advanced function's begin/process lifetime, its cross-hop
/// state ($localCachedCopy, normalized $Solution), and its cross-record state (the function-interrupt
/// latch and $sql). Surface pinned by migration/baselines/Install-DbaMaintenanceSolution.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Install, "DbaMaintenanceSolution", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class InstallDbaMaintenanceSolutionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database where the maintenance solution objects will be installed.</summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    public string Database { get; set; } = "master";

    /// <summary>Root directory path where backup files will be stored by the maintenance jobs.</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    public string? BackupLocation { get; set; }

    /// <summary>Retention period in hours before backup files are automatically deleted by cleanup jobs.</summary>
    [Parameter(Position = 4)]
    public int CleanupTime { get; set; }

    /// <summary>Directory path where SQL Agent jobs will write their output log files.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    public string? OutputFileDirectory { get; set; }

    /// <summary>Forces replacement of existing Ola Hallengren objects.</summary>
    [Parameter]
    public SwitchParameter ReplaceExisting { get; set; }

    /// <summary>Enables command logging to the CommandLog table.</summary>
    [Parameter]
    public SwitchParameter LogToTable { get; set; }

    /// <summary>Which maintenance components to install: All, Backup, IntegrityCheck, or IndexOptimize.</summary>
    [Parameter(Position = 6)]
    [PsStringArrayCast]
    [ValidateSet("All", "Backup", "IntegrityCheck", "IndexOptimize")]
    public string[] Solution { get; set; } = { "All" };

    /// <summary>Creates pre-configured SQL Agent jobs for automated maintenance.</summary>
    [Parameter]
    public SwitchParameter InstallJobs { get; set; }

    /// <summary>Automatically creates optimized job schedules for backup operations.</summary>
    [Parameter(Position = 7)]
    [PsStringArrayCast]
    [ValidateSet("WeeklyFull", "DailyFull", "NoDiff", "FifteenMinuteLog", "HourlyLog")]
    public string[]? AutoScheduleJobs { get; set; }

    /// <summary>Start time for the auto-scheduled backup jobs, in HHmmss format.</summary>
    [Parameter(Position = 8)]
    [PsStringCast]
    public string StartTime { get; set; } = "011500";

    /// <summary>Install from a local zip/folder instead of downloading.</summary>
    [Parameter(Position = 9)]
    [PsStringCast]
    public string? LocalFile { get; set; }

    /// <summary>Force a refresh of the local cached copy of the software.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>Creates the Queue and QueueDatabase tables for parallel execution.</summary>
    [Parameter]
    public SwitchParameter InstallParallel { get; set; }

    /// <summary>Adds automatic backup-type conversion to DIFF and LOG backup jobs.</summary>
    [Parameter]
    public SwitchParameter ChangeBackupType { get; set; }

    /// <summary>Controls backup compression in job commands: Default, ForceOn, ForceOff, or Remove.</summary>
    [Parameter(Position = 10)]
    [PsStringCast]
    [ValidateSet("Default", "ForceOn", "ForceOff", "Remove")]
    public string Compress { get; set; } = "Default";

    /// <summary>Adds copy-only backups to the backup job commands.</summary>
    [Parameter]
    public SwitchParameter CopyOnly { get; set; }

    /// <summary>Controls backup verification in job commands: Default, ForceOn, ForceOff, or Remove.</summary>
    [Parameter(Position = 11)]
    [PsStringCast]
    [ValidateSet("Default", "ForceOn", "ForceOff", "Remove")]
    public string Verify { get; set; } = "Default";

    /// <summary>Controls checksum validation in job commands: Default, ForceOn, ForceOff, or Remove.</summary>
    [Parameter(Position = 12)]
    [PsStringCast]
    [ValidateSet("Default", "ForceOn", "ForceOff", "Remove")]
    public string CheckSum { get; set; } = "Default";

    /// <summary>Minimum modification percentage before ChangeBackupType converts a differential to full.</summary>
    [Parameter(Position = 13)]
    [ValidateRange(0, 100)]
    public int ModificationLevel { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Begin -> process carriers: the source begin resolves $localCachedCopy (internet detection +
    // Save-DbaCommunitySoftware / bundled fallback) and normalizes $Solution ('All' collapses the set);
    // the process body reads both. Separate hops don't share the begin scope, so carry them.
    private object? _localCachedCopy;
    private object? _solution;
    // Cross-record function-interrupt latch. The source is ONE advanced function whose $interrupt flag
    // is function-scoped, so it persists across pipeline records: a begin validation Stop-Function, or the
    // process "already exists" Stop-Function (source :480, the ONLY non-Continue Stop-Function in the body),
    // makes the process block's leading Test-FunctionInterrupt return early on EVERY later record. A
    // per-record hop resets that flag, so we carry it and gate ProcessRecord with it (reproduce-not-sanitize).
    private bool _interrupted;
    // Cross-record $sql carrier. $sql is function-scoped, assigned inside the file-install loop (source :586)
    // and read at :884 to decide whether a result object is emitted; a per-record hop would reset it. Seed it.
    private object? _carriedSql;
    // The process body emits arbitrary result objects, so the process-complete sentinel is keyed on this
    // per-invocation GUID token compared ORDINAL (a property-name/truthiness key could collide with real output).
    private readonly string _processToken = Guid.NewGuid().ToString("N");

    protected override void BeginProcessing()
    {
        // Begin STREAMS (not buffered InvokeScoped): the source begin can emit a Stop-Function warning
        // (validation) and THEN Save-DbaCommunitySoftware, so buffering would risk losing an emit before a
        // later terminating failure (DEF-001/T1 emit-then-terminate, in begin). Streaming forwards it first.
        bool completed = false;
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__InstallMaintSolBeginComplete"]?.Value))
            {
                _localCachedCopy = UnwrapHopValue(item.Properties["LocalCachedCopy"]?.Value);
                _solution = UnwrapHopValue(item.Properties["Solution"]?.Value);
                _interrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
                completed = true;
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, BeginScript,
            Force.ToBool(), Solution, InstallJobs.ToBool(), BackupLocation, Verify, AutoScheduleJobs,
            ReplaceExisting.ToBool(), LocalFile, EnableException.ToBool(), this,
            WasBound("CleanupTime"), WasBound("AutoScheduleJobs"),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
        if (!completed)
            _interrupted = true;
    }

    protected override void ProcessRecord()
    {
        // Source :454 - the function-scoped interrupt latch (from begin, or a prior record's :480
        // Stop-Function) returns the whole process block early. Interrupted is the base pipeline-stop guard.
        if (_interrupted || Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && string.Equals(
                item.Properties["__InstallMaintSolProcessComplete"]?.Value as string, _processToken, StringComparison.Ordinal))
            {
                _carriedSql = UnwrapHopValue(item.Properties["Sql"]?.Value);
                _interrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, BackupLocation, CleanupTime, OutputFileDirectory,
            _solution, LogToTable.ToBool(), InstallJobs.ToBool(), InstallParallel.ToBool(), ReplaceExisting.ToBool(),
            AutoScheduleJobs, StartTime, ChangeBackupType.ToBool(), ModificationLevel, Compress, CopyOnly.ToBool(),
            Verify, CheckSum, _localCachedCopy, EnableException.ToBool(), this, _processToken, _carriedSql,
            WasBound("ReplaceExisting"), WasBound("BackupLocation"),
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

    // Test-Bound replacement: whether the caller explicitly bound this parameter (module scope cannot
    // see the caller's $PSBoundParameters, so the flag is computed here and carried in).
    private bool WasBound(string name)
    {
        return MyInvocation.BoundParameters.ContainsKey(name);
    }

    private const string BeginScript = """
param($Force, $Solution, $InstallJobs, $BackupLocation, $Verify, $AutoScheduleJobs, $ReplaceExisting, $LocalFile, $EnableException, $__realCmdlet, $__boundCleanupTime, $__boundAutoScheduleJobs, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param($Force, [string[]]$Solution, $InstallJobs, [string]$BackupLocation, [string]$Verify, [string[]]$AutoScheduleJobs, $ReplaceExisting, [string]$LocalFile, $EnableException, $__realCmdlet, $__boundCleanupTime, $__boundAutoScheduleJobs)

    # The begin body has early returns (validation Stop-Function; return); dot-source it so the return
    # exits only this block and the trailing sentinel (carrying $localCachedCopy/$Solution/Interrupted) still runs.
    . {
        if ($Force) { $ConfirmPreference = 'none' }

        if ($Solution -contains 'All') {
            $Solution = @('All');
        }

        if ($InstallJobs -and $Solution -notcontains 'All') {
            Stop-Function -Message "Jobs can only be created for all solutions. To create SQL Agent jobs you need to use '-Solution All' (or not specify the Solution and let it default to All) and '-InstallJobs'." -FunctionName Install-DbaMaintenanceSolution
            return
        }

        if ($InstallJobs -and $BackupLocation -eq "NUL" -and $Verify -notin "ForceOff", "Remove") {
            Stop-Function -Message "Verify is not supported when backing up to NUL. Either backup to a different directory or set -Verify to 'ForceOff' or 'Remove'." -FunctionName Install-DbaMaintenanceSolution
            return
        }

        if (($__boundCleanupTime) -and -not $InstallJobs) {
            Stop-Function -Message "CleanupTime is only useful when installing jobs. To install jobs, please use '-InstallJobs' in addition to CleanupTime." -FunctionName Install-DbaMaintenanceSolution
            return
        }

        if ($__boundAutoScheduleJobs) {
            if (-not $InstallJobs) {
                Stop-Function -Message "AutoScheduleJobs is only useful when installing jobs. To create and schedule SQL Agent jobs, please use '-InstallJobs' in addition to AutoScheduleJobs." -FunctionName Install-DbaMaintenanceSolution
                return
            }

            $hasWeeklyFull = "WeeklyFull" -in $AutoScheduleJobs
            $hasDailyFull = "DailyFull" -in $AutoScheduleJobs

            if ($hasWeeklyFull -eq $hasDailyFull) {
                Stop-Function -Message "AutoScheduleJobs requires exactly one full backup schedule. Specify either 'WeeklyFull' or 'DailyFull'." -FunctionName Install-DbaMaintenanceSolution
                return
            }
        }

        if ($ReplaceExisting -eq $true) {
            Write-ProgressHelper -ExcludePercent -Message "If Ola Hallengren's scripts are found, we will drop and recreate them"
        }


        # does this machine have internet access to download the files if required?
        if (-not $isLinux -and -not $isMacOs) {
            if ((Get-Command -Name Get-NetConnectionProfile -ErrorAction SilentlyContinue)) {
                $script:internet = (Get-NetConnectionProfile -ErrorAction SilentlyContinue).IPv4Connectivity -contains "Internet"
            } else {
                try {
                    $network = [Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}")
                    $script:internet = ([Activator]::CreateInstance($network)).GetNetworkConnections() | ForEach-Object { $_.GetNetwork().GetConnectivity() } | Where-Object { ($_ -band 64) -eq 64 }
                } catch {
                    # probably a container with internet
                    $script:internet = $true
                }
            }

            if (-not $internet) {
                Write-Message -Level Verbose -Message "No internet connection found, using included copy of Maintenance Solution." -FunctionName Install-DbaMaintenanceSolution -ModuleName "dbatools"
                $localCachedCopy = [System.IO.Path]::Combine($script:PSModuleRoot, "bin", "maintenancesolution")
            }
        }

        if (-not $localCachedCopy) {
            # Do we need a fresly cached version of the software?
            $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
            $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child 'sql-server-maintenance-solution-main'
            if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
                if ($__realCmdlet.ShouldProcess('MaintenanceSolution', 'Update local cached copy of the software')) {
                    try {
                        Save-DbaCommunitySoftware -Software MaintenanceSolution -LocalFile $LocalFile -EnableException
                    } catch {
                        # this will help offline Linux machines too
                        Write-Message -Level Verbose -Message "No internet connection found, using included copy of Maintenance Solution." -FunctionName Install-DbaMaintenanceSolution -ModuleName "dbatools"
                        $localCachedCopy = [System.IO.Path]::Combine($script:PSModuleRoot, "bin", "maintenancesolution")
                    }
                }
            }
        }
    }

    [pscustomobject]@{ __InstallMaintSolBeginComplete = $true; LocalCachedCopy = $localCachedCopy; Solution = $Solution; Interrupted = [bool](Test-FunctionInterrupt) }
} $Force $Solution $InstallJobs $BackupLocation $Verify $AutoScheduleJobs $ReplaceExisting $LocalFile $EnableException $__realCmdlet $__boundCleanupTime $__boundAutoScheduleJobs @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $BackupLocation, $CleanupTime, $OutputFileDirectory, $Solution, $LogToTable, $InstallJobs, $InstallParallel, $ReplaceExisting, $AutoScheduleJobs, $StartTime, $ChangeBackupType, $ModificationLevel, $Compress, $CopyOnly, $Verify, $CheckSum, $localCachedCopy, $EnableException, $__realCmdlet, $__processToken, $__carriedSql, $__boundReplaceExisting, $__boundBackupLocation, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string]$Database, [string]$BackupLocation, [int]$CleanupTime, [string]$OutputFileDirectory, [string[]]$Solution, $LogToTable, $InstallJobs, $InstallParallel, $ReplaceExisting, [string[]]$AutoScheduleJobs, [string]$StartTime, $ChangeBackupType, [int]$ModificationLevel, [string]$Compress, $CopyOnly, [string]$Verify, [string]$CheckSum, $localCachedCopy, $EnableException, $__realCmdlet, $__processToken, $__carriedSql, $__boundReplaceExisting, $__boundBackupLocation)

    # Cross-record carrier: $sql is function-scoped in the source; seed it with the prior record's value
    # BEFORE the loop so the :884 result-emission test reproduces the function world across pipeline records.
    $sql = $__carriedSql

    # Relocated from the source begin block (defined there, invoked only here): this helper closes over
    # $Database/$BackupLocation/$CleanupTime/$OutputFileDirectory/$LogToTable/$InstallJobs - all in scope
    # here - and is called AFTER $BackupLocation is resolved below, so its closure sees the same values the
    # source's begin-defined function would (the begin scope does not survive into a separate process hop).
    function Get-DbaOlaWithParameters($listOfFiles) {

        $fileContents = @{ }
        foreach ($file in $listOfFiles) {
            $fileContents[$file] = Get-Content -Path $file -Raw
        }

        foreach ($file in $($fileContents.Keys)) {
            # In which database we install
            if ($Database -ne 'master') {
                $findDB = 'USE [master]'
                $replaceDB = 'USE [' + $Database + ']'
                $fileContents[$file] = $fileContents[$file].Replace($findDB, $replaceDB)
            }

            # Backup location
            if ($BackupLocation) {
                $findBKP = 'DECLARE @BackupDirectory nvarchar(max)     = NULL'
                $replaceBKP = 'DECLARE @BackupDirectory nvarchar(max)     = N''' + $BackupLocation + ''''
                $fileContents[$file] = $fileContents[$file].Replace($findBKP, $replaceBKP)
            }

            # CleanupTime
            if ($CleanupTime -ne 0) {
                $findCleanupTime = 'DECLARE @CleanupTime int                   = NULL'
                $replaceCleanupTime = 'DECLARE @CleanupTime int                   = ' + $CleanupTime
                $fileContents[$file] = $fileContents[$file].Replace($findCleanupTime, $replaceCleanupTime)
            }

            # OutputFileDirectory
            if ($OutputFileDirectory) {
                $findOutputFileDirectory = 'DECLARE @OutputFileDirectory nvarchar(max) = NULL'
                $replaceOutputFileDirectory = 'DECLARE @OutputFileDirectory nvarchar(max) = N''' + $OutputFileDirectory + ''''
                $fileContents[$file] = $fileContents[$file].Replace($findOutputFileDirectory, $replaceOutputFileDirectory)
            }

            # LogToTable
            if (!$LogToTable) {
                $findLogToTable = "DECLARE @LogToTable nvarchar(max)          = 'Y'"
                $replaceLogToTable = "DECLARE @LogToTable nvarchar(max)          = 'N'"
                $fileContents[$file] = $fileContents[$file].Replace($findLogToTable, $replaceLogToTable)
            }

            # Create Jobs
            if (-not $InstallJobs) {
                $findCreateJobs = "DECLARE @CreateJobs nvarchar(max)          = 'Y'"
                $replaceCreateJobs = "DECLARE @CreateJobs nvarchar(max)          = 'N'"
                $fileContents[$file] = $fileContents[$file].Replace($findCreateJobs, $replaceCreateJobs)
            }
        }
        return $fileContents
    }

    # The process body has an early return (:454) and loop 'continue's; dot-source it so the return exits
    # only this block and the trailing sentinel (carrying $sql/Interrupted) still runs.
    . {
        if (Test-FunctionInterrupt) {
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -NonPooledConnection
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Install-DbaMaintenanceSolution
            }

            if ($server.Version.Major -lt 14) {
                Stop-Function -Message "The Maintenance Solution is not supported on SQL Server version $($server.Version). Skipping $instance." -Target $instance -Continue -FunctionName Install-DbaMaintenanceSolution
            }

            $db = $server.Databases[$Database]

            if ($null -eq $db) {
                Stop-Function -Message "Database $Database not found on $instance. Skipping." -Target $instance -Continue -FunctionName Install-DbaMaintenanceSolution
            }

            if ((-not $__boundReplaceExisting)) {
                $procs = Get-DbaModule -SqlInstance $server -Database $Database | Where-Object Name -in 'CommandExecute', 'DatabaseBackup', 'DatabaseIntegrityCheck', 'IndexOptimize'
                $tables = Get-DbaDbTable -SqlInstance $server -Database $Database -Table CommandLog, Queue, QueueDatabase -IncludeSystemDBs | Where-Object Database -eq $Database

                if ($null -ne $procs -or $null -ne $tables) {
                    Stop-Function -Message "The Maintenance Solution already exists in $Database on $instance. Use -ReplaceExisting to automatically drop and recreate." -FunctionName Install-DbaMaintenanceSolution
                    continue
                }
            }

            if ((-not $__boundBackupLocation)) {
                $BackupLocation = (Get-DbaDefaultPath -SqlInstance $server).Backup
            }
            Write-ProgressHelper -ExcludePercent -Message "Ola Hallengren's solution will be installed on database $Database"

            if ($Solution -notcontains 'All') {
                $required = @('CommandExecute.sql')
            }

            if ($LogToTable -and $InstallJobs -eq $false) {
                $required += 'CommandLog.sql'
            }

            if ($Solution -contains 'Backup') {
                $required += 'DatabaseBackup.sql'
            }

            if ($Solution -contains 'IntegrityCheck') {
                $required += 'DatabaseIntegrityCheck.sql'
            }

            if ($Solution -contains 'IndexOptimize') {
                $required += 'IndexOptimize.sql'
            }

            if ($Solution -contains 'All' -and $InstallJobs) {
                $required += 'MaintenanceSolution.sql'
            }

            if ($Solution -contains 'All' -and $InstallJobs -eq $false) {
                $required += 'CommandExecute.sql'
                $required += 'DatabaseBackup.sql'
                $required += 'DatabaseIntegrityCheck.sql'
                $required += 'IndexOptimize.sql'
            }

            if ($InstallParallel) {
                $required += 'Queue.sql'
                $required += 'QueueDatabase.sql'
            }

            $listOfFiles = Get-ChildItem -Filter "*.sql" -Path $localCachedCopy -Recurse | Select-Object -ExpandProperty FullName

            $fileContents = Get-DbaOlaWithParameters -listOfFiles $listOfFiles

            $cleanupQuery = $null
            if ($ReplaceExisting) {
                [string]$cleanupQuery = $("
                            IF OBJECT_ID('[dbo].[CommandExecute]', 'P') IS NOT NULL
                                DROP PROCEDURE [dbo].[CommandExecute];
                            IF OBJECT_ID('[dbo].[DatabaseBackup]', 'P') IS NOT NULL
                                DROP PROCEDURE [dbo].[DatabaseBackup];
                            IF OBJECT_ID('[dbo].[DatabaseIntegrityCheck]', 'P') IS NOT NULL
                                DROP PROCEDURE [dbo].[DatabaseIntegrityCheck];
                            IF OBJECT_ID('[dbo].[IndexOptimize]', 'P') IS NOT NULL
                                DROP PROCEDURE [dbo].[IndexOptimize];
                            ")

                if ($LogToTable) {
                    $cleanupQuery += $("
                            IF OBJECT_ID('[dbo].[CommandLog]', 'U') IS NOT NULL
                                DROP TABLE [dbo].[CommandLog];
                            ")
                }

                if ($InstallParallel) {
                    $cleanupQuery += $("
                            IF OBJECT_ID('[dbo].[QueueDatabase]', 'U') IS NOT NULL
                                DROP TABLE [dbo].[QueueDatabase];
                            IF OBJECT_ID('[dbo].[Queue]', 'U') IS NOT NULL
                                DROP TABLE [dbo].[Queue];
                            ")
                }

                if ($__realCmdlet.ShouldProcess($instance, "Dropping all objects created by Ola's Maintenance Solution")) {
                    Write-ProgressHelper -ExcludePercent -Message "Dropping objects created by Ola's Maintenance Solution"
                    $null = $db.Invoke($cleanupQuery)
                }

                # Remove Ola's Jobs
                if ($InstallJobs -and $ReplaceExisting) {
                    Write-ProgressHelper -ExcludePercent -Message "Removing existing SQL Agent Jobs created by Ola's Maintenance Solution"
                    $jobs = Get-DbaAgentJob -SqlInstance $server | Where-Object Description -match "hallengren"
                    if ($jobs) {
                        $jobs | ForEach-Object {
                            if ($__realCmdlet.ShouldProcess($instance, "Dropping job $_.name")) {
                                $null = Remove-DbaAgentJob -SqlInstance $server -Job $_.name -Confirm:$false
                            }
                        }
                    }
                }
            }

            Write-ProgressHelper -ExcludePercent -Message "Installing on server $instance, database $Database"

            $result = "Success"
            foreach ($file in $fileContents.Keys | Sort-Object) {
                $shortFileName = Split-Path $file -Leaf
                if ($required.Contains($shortFileName)) {
                    if ($__realCmdlet.ShouldProcess($instance, "Installing $shortFileName")) {
                        Write-ProgressHelper -ExcludePercent -Message "Installing $shortFileName"
                        $sql = $fileContents[$file]
                        try {
                            # We use Invoke-DbaQuery because using ExecuteNonQuery with long batches causes problems on AppVeyor.
                            $null = Invoke-DbaQuery -SqlInstance $server -Database $Database -Query $sql -EnableException
                        } catch {
                            $result = "Failed"
                            Stop-Function -Message "Could not execute $shortFileName in $Database on $instance" -ErrorRecord $_ -Target $db -Continue -FunctionName Install-DbaMaintenanceSolution
                        }
                    }
                }
            }

            if ($AutoScheduleJobs) {
                Write-ProgressHelper -ExcludePercent -Message "Scheduling jobs"

                <#
                    WeeklyFull will create weekly full, daily differential and 15 minute log backups.

                    To skip diffs, specify NoDiff in the values. To perform log backups each hour instead of every
                    15 minutes, specify HourlyLog in the values.

                    System databases:
                    Full backup every day
                    Integrity check one day per week

                    I (Ola) recommend that you run a full backup after the index maintenance. The following differential backups will then be small. I also recommend that you perform the full backup after the integrity check. Then you know that the integrity of the backup is okay.

                    Cleanup:

                    sp_delete_backuphistory one day per week
                    sp_purge_jobhistory one day per week
                    CommandLog cleanup one day per week
                    Output file cleanup one day per week
                #>
                $null = $server.Refresh()
                $null = $server.JobServer.Jobs.Refresh()

                $schedules = Get-DbaAgentSchedule -SqlInstance $server
                $sunday = $schedules | Where-Object FrequencyInterval -eq 1
                $start = $StartTime
                $hour = New-TimeSpan -Hours 1
                $twohours = New-TimeSpan -Hours 2
                $twelvehours = New-TimeSpan -Hours 12
                $twentyfourhours = New-TimeSpan -Hours 24

                if ($sunday) {
                    foreach ($time in $sunday) {
                        if ($time.ActiveStartTimeOfDay) {
                            if ($time.ActiveStartTimeOfDay.ToString().Replace(":", "") -eq $start) {
                                $start = $time.ActiveStartTimeOfDay.Add($hour).ToString().Replace(":", "")
                            }
                        }
                    }
                }

                if ("WeeklyFull" -in $AutoScheduleJobs) {
                    $fullparams = @{
                        SqlInstance       = $server
                        Job               = "DatabaseBackup - USER_DATABASES - FULL"
                        Schedule          = "Weekly Full User Backup"
                        FrequencyType     = "Weekly"
                        FrequencyInterval = "Sunday" # 1
                        StartTime         = $start
                        Force             = $true
                    }
                } elseif ("DailyFull" -in $AutoScheduleJobs) {
                    $fullparams = @{
                        SqlInstance       = $server
                        Job               = "DatabaseBackup - USER_DATABASES - FULL"
                        Schedule          = "Daily Full User Backup"
                        FrequencyType     = "Daily"
                        FrequencyInterval = "EveryDay"
                        StartTime         = $start
                        Force             = $true
                    }
                }

                if ("WeeklyFull" -in $AutoScheduleJobs -or "DailyFull" -in $AutoScheduleJobs) {
                    $fullschedule = New-DbaAgentSchedule @fullparams
                }

                if ($fullschedule.ActiveStartTimeOfDay) {
                    $systemdaily = $fullschedule.ActiveStartTimeOfDay.Add($twohours) -replace ":|\-|1\.", ""
                } else {
                    $systemdaily = "031500"
                }

                $fullsystemparams = @{
                    SqlInstance       = $server
                    Job               = "DatabaseBackup - SYSTEM_DATABASES - FULL"
                    Schedule          = "Daily Full System Backup"
                    FrequencyType     = "Daily"
                    FrequencyInterval = "EveryDay"
                    StartTime         = $systemdaily
                    Force             = $true
                }

                $null = New-DbaAgentSchedule @fullsystemparams

                if ($fullschedule.ActiveStartTimeOfDay) {
                    $integrity = $fullschedule.ActiveStartTimeOfDay.Subtract($twelvehours) -replace ":|\-|1\.", ""
                } else {
                    $integrity = "044500"
                }

                $integrityparams = @{
                    SqlInstance       = $server
                    Job               = "DatabaseIntegrityCheck - SYSTEM_DATABASES", "DatabaseIntegrityCheck - USER_DATABASES"
                    Schedule          = "Weekly Integrity Check"
                    FrequencyType     = "Weekly"
                    FrequencyInterval = "Saturday" # 6
                    StartTime         = $integrity
                    Force             = $true
                }

                $null = New-DbaAgentSchedule @integrityparams

                if ($fullschedule.ActiveStartTimeOfDay) {
                    $indexoptimize = $fullschedule.ActiveStartTimeOfDay.Subtract($twentyfourhours) -replace ":|\-|1\.", ""
                } else {
                    $indexoptimize = "224500"
                }


                $integrityparams = @{
                    SqlInstance       = $server
                    Job               = "IndexOptimize - USER_DATABASES"
                    Schedule          = "Weekly Index Optimization"
                    FrequencyType     = "Weekly"
                    FrequencyInterval = "Saturday" # 6
                    StartTime         = $indexoptimize
                    Force             = $true
                }

                $null = New-DbaAgentSchedule @integrityparams

                if ("NoDiff" -notin $AutoScheduleJobs -and "DailyFull" -notin $AutoScheduleJobs) {
                    $diffparams = @{
                        SqlInstance       = $server
                        Job               = "DatabaseBackup - USER_DATABASES - DIFF"
                        Schedule          = "Daily Diff Backup"
                        FrequencyType     = "Weekly"
                        FrequencyInterval = 126 # all days but sunday
                        StartTime         = $start
                        Force             = $true
                    }
                    $null = New-DbaAgentSchedule @diffparams
                }

                if ("HourlyLog" -in $AutoScheduleJobs) {
                    $logparams = @{
                        SqlInstance             = $server
                        Job                     = "DatabaseBackup - USER_DATABASES - LOG"
                        Schedule                = "Hourly Log Backup"
                        FrequencyType           = "Daily"
                        FrequencyInterval       = 1
                        FrequencySubDayType     = "Hours"
                        FrequencySubDayInterval = 1
                        StartTime               = "000000"
                        Force                   = $true
                    }
                } else {
                    $logparams = @{
                        SqlInstance             = $server
                        Job                     = "DatabaseBackup - USER_DATABASES - LOG"
                        Schedule                = "15 Minute Log Backup"
                        FrequencyType           = "Daily"
                        FrequencyInterval       = 1
                        FrequencySubDayInterval = 15
                        FrequencySubDayType     = "Minute"
                        StartTime               = "000000"
                        Force                   = $true
                    }
                }
                $null = New-DbaAgentSchedule @logparams

                # You know... why not? These are lightweight tasks.
                $cleanparams = @{
                    SqlInstance       = $server
                    Job               = "Output File Cleanup", "sp_delete_backuphistory", "sp_purge_jobhistory", "CommandLog Cleanup"
                    Schedule          = "Weekly Clean and Purge"
                    FrequencyType     = "Weekly"
                    FrequencyInterval = "Sunday"
                    StartTime         = "235000" # 11:50 pm
                    Force             = $true
                }

                $null = New-DbaAgentSchedule @cleanparams
            }

            # Modify backup job steps to include additional parameters
            if ($InstallJobs) {
                Write-ProgressHelper -ExcludePercent -Message "Applying additional backup parameters to job steps"

                $null = $server.Refresh()
                $null = $server.JobServer.Jobs.Refresh()

                $backupJobs = Get-DbaAgentJob -SqlInstance $server | Where-Object Description -match "hallengren"

                foreach ($job in $backupJobs) {
                    if ($job.Name -notmatch "DatabaseBackup") {
                        continue
                    }

                    $jobSteps = Get-DbaAgentJobStep -SqlInstance $server -Job $job.Name

                    foreach ($step in $jobSteps) {
                        $originalCommand = $step.Command
                        $modifiedCommand = $originalCommand

                        # Add ChangeBackupType parameter for DIFF and LOG backups only
                        if ($ChangeBackupType -and ($job.Name -match "DIFF|LOG")) {
                            if ($modifiedCommand -notmatch "@ChangeBackupType") {
                                $modifiedCommand = $modifiedCommand -replace "(@LogToTable = '[YN]')", "`$1,$([System.Environment]::NewLine)@ChangeBackupType = 'Y'"
                            }
                        }

                        # Add ModificationLevel parameter for jobs with ChangeBackupType
                        if ($ModificationLevel -gt 0 -and ($job.Name -match "DIFF")) {
                            if ($modifiedCommand -notmatch "@ModificationLevel") {
                                $modifiedCommand = $modifiedCommand -replace "(@LogToTable = '[YN]')", "`$1,$([System.Environment]::NewLine)@ModificationLevel = $ModificationLevel"
                            }
                        }

                        # Compress parameter for all backup jobs
                        # Default: do not include @Compress (instance-level setting applies)
                        if ($Compress -eq "ForceOn") {
                            $modifiedCommand = $modifiedCommand -replace "@Compress = 'N'", "@Compress = 'Y'"
                            if ($modifiedCommand -notmatch "@Compress") {
                                $modifiedCommand = $modifiedCommand -replace "(@LogToTable = '[YN]')", "`$1,$([System.Environment]::NewLine)@Compress = 'Y'"
                            }
                        } elseif ($Compress -eq "ForceOff") {
                            $modifiedCommand = $modifiedCommand -replace "@Compress = 'Y'", "@Compress = 'N'"
                            if ($modifiedCommand -notmatch "@Compress") {
                                $modifiedCommand = $modifiedCommand -replace "(@LogToTable = '[YN]')", "`$1,$([System.Environment]::NewLine)@Compress = 'N'"
                            }
                        } elseif ($Compress -eq "Remove") {
                            $modifiedCommand = $modifiedCommand -replace "@Compress = '[YN]',\r?\n", ""
                            $modifiedCommand = $modifiedCommand -replace ",\r?\n@Compress = '[YN]'", ""
                        }

                        # Add CopyOnly parameter for all backup jobs
                        if ($CopyOnly) {
                            if ($modifiedCommand -notmatch "@CopyOnly") {
                                $modifiedCommand = $modifiedCommand -replace "(@LogToTable = '[YN]')", "`$1,$([System.Environment]::NewLine)@CopyOnly = 'Y'"
                            }
                        }

                        # Verify parameter for all backup jobs
                        # Ola includes @Verify = 'Y' by default. Default: leave unchanged.
                        if ($Verify -eq "ForceOn") {
                            $modifiedCommand = $modifiedCommand -replace "@Verify = 'N'", "@Verify = 'Y'"
                            if ($modifiedCommand -notmatch "@Verify") {
                                $modifiedCommand = $modifiedCommand -replace "(@LogToTable = '[YN]')", "`$1,$([System.Environment]::NewLine)@Verify = 'Y'"
                            }
                        } elseif ($Verify -eq "ForceOff") {
                            $modifiedCommand = $modifiedCommand -replace "@Verify = 'Y'", "@Verify = 'N'"
                            if ($modifiedCommand -notmatch "@Verify") {
                                $modifiedCommand = $modifiedCommand -replace "(@LogToTable = '[YN]')", "`$1,$([System.Environment]::NewLine)@Verify = 'N'"
                            }
                        } elseif ($Verify -eq "Remove") {
                            $modifiedCommand = $modifiedCommand -replace "@Verify = '[YN]',\r?\n", ""
                            $modifiedCommand = $modifiedCommand -replace ",\r?\n@Verify = '[YN]'", ""
                        }

                        # CheckSum parameter for all backup jobs
                        # Ola includes @Checksum = 'Y' by default. Default: leave unchanged.
                        if ($CheckSum -eq "ForceOn") {
                            $modifiedCommand = $modifiedCommand -replace "@Checksum = 'N'", "@Checksum = 'Y'"
                            if ($modifiedCommand -notmatch "@Checksum") {
                                $modifiedCommand = $modifiedCommand -replace "(@LogToTable = '[YN]')", "`$1,$([System.Environment]::NewLine)@Checksum = 'Y'"
                            }
                        } elseif ($CheckSum -eq "ForceOff") {
                            $modifiedCommand = $modifiedCommand -replace "@Checksum = 'Y'", "@Checksum = 'N'"
                            if ($modifiedCommand -notmatch "@Checksum") {
                                $modifiedCommand = $modifiedCommand -replace "(@LogToTable = '[YN]')", "`$1,$([System.Environment]::NewLine)@Checksum = 'N'"
                            }
                        } elseif ($CheckSum -eq "Remove") {
                            $modifiedCommand = $modifiedCommand -replace "@Checksum = '[YN]',\r?\n", ""
                            $modifiedCommand = $modifiedCommand -replace ",\r?\n@Checksum = '[YN]'", ""
                        }

                        # Update job step if command was modified
                        if ($modifiedCommand -ne $originalCommand) {
                            if ($__realCmdlet.ShouldProcess($instance, "Updating job step '$($step.Name)' in job '$($job.Name)'")) {
                                $splatJobStep = @{
                                    SqlInstance = $server
                                    Job         = $job.Name
                                    StepName    = $step.Name
                                    Command     = $modifiedCommand
                                }
                                $null = Set-DbaAgentJobStep @splatJobStep
                            }
                        }
                    }
                }
            }

            if ($sql) {
                # then whatif wasn't passed
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Results      = $result
                }
            }

            # Close non-pooled connection as this is not done automatically. If it is a reused Server SMO, connection will be opened again automatically on next request.
            $null = $server | Disconnect-DbaInstance
        }

        Write-ProgressHelper -ExcludePercent -Message "Installation complete"
        Write-ProgressHelper -Completed
    }

    [pscustomobject]@{ __InstallMaintSolProcessComplete = $__processToken; Sql = $sql; Interrupted = [bool](Test-FunctionInterrupt) }
} $SqlInstance $SqlCredential $Database $BackupLocation $CleanupTime $OutputFileDirectory $Solution $LogToTable $InstallJobs $InstallParallel $ReplaceExisting $AutoScheduleJobs $StartTime $ChangeBackupType $ModificationLevel $Compress $CopyOnly $Verify $CheckSum $localCachedCopy $EnableException $__realCmdlet $__processToken $__carriedSql $__boundReplaceExisting $__boundBackupLocation @__commonParameters 3>&1 2>&1
""";
}

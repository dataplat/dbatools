#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Backs up each database with a checksummed, restore-verified golden backup, builds a SQL Agent
/// restore job, drops the original, runs the restore job, re-checks the restored copy, and drops the
/// test copy. The connect/validate prep (begin), the per-database backup/job/drop/restore/verify loop
/// with every ShouldProcess gate (process), and the closing duration message (end) remain a
/// module-scoped PowerShell compatibility hop; this cmdlet supplies the real ShouldProcess runtime
/// (ConfirmImpact Medium), preserves the advanced function's begin/process/end lifetime, carries the
/// begin-connected source/destination SMO servers and resolved database set into the process hop, and
/// carries the process $start into the end hop. The single-value ValueFromPipeline SqlInstance means
/// begin connects to the argument-bound instance exactly as the source does. Surface pinned by
/// migration/baselines/Remove-DbaDatabaseSafely.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDatabaseSafely", DefaultParameterSetName = "Default", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class RemoveDbaDatabaseSafelyCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Default")]
    public DbaInstanceParameter SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1, ParameterSetName = "Default")]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>One or more databases to safely remove with a validated backup.</summary>
    [Parameter(Position = 2, ParameterSetName = "Default")]
    [Alias("Name")]
    public object[]? Database { get; set; }

    /// <summary>The SQL Server instance where the restore-test Agent job is created and executed. Defaults to SqlInstance.</summary>
    [Parameter(Position = 3, ParameterSetName = "Default")]
    public DbaInstanceParameter? Destination { get; set; }

    /// <summary>Credentials for the destination instance when different from SqlCredential.</summary>
    [Parameter(Position = 4, ParameterSetName = "Default")]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Directory where the final database backups are stored before deletion.</summary>
    [Parameter(Mandatory = true, Position = 5, ParameterSetName = "Default")]
    [PsStringCast]
    public string BackupFolder { get; set; } = null!;

    /// <summary>SQL Agent job category for the restore jobs. Defaults to 'Rationalisation'.</summary>
    [Parameter(Position = 6, ParameterSetName = "Default")]
    public string CategoryName { get; set; } = "Rationalisation";

    /// <summary>Owner login for the created restore job. Defaults to the destination 'sa' login.</summary>
    [Parameter(Position = 7, ParameterSetName = "Default")]
    public string? JobOwner { get; set; }

    /// <summary>Backup compression behavior: Default (server setting), On, or Off.</summary>
    [Parameter(Position = 8, ParameterSetName = "Default")]
    [ValidateSet("Default", "On", "Off")]
    public string BackupCompression { get; set; } = "Default";

    /// <summary>Removes all user databases (excluding system databases) from the source server.</summary>
    [Parameter(ParameterSetName = "Default")]
    public SwitchParameter AllDatabases { get; set; }

    /// <summary>Skips the initial DBCC CHECKDB integrity check before backup.</summary>
    [Parameter(ParameterSetName = "Default")]
    [Alias("NoCheck")]
    public SwitchParameter NoDbccCheckDb { get; set; }

    /// <summary>Maintains original database file paths during the test restore.</summary>
    [Parameter(ParameterSetName = "Default")]
    public SwitchParameter ReuseSourceFolderStructure { get; set; }

    /// <summary>Continues the removal even when DBCC integrity checks detect corruption.</summary>
    [Parameter(ParameterSetName = "Default")]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Begin -> process carriers. The source begin connects $sourceserver/$destserver, resolves
    // $source/$destination (DomainInstanceName), the $jobowner default (Get-SqlSaLogin) and the
    // effective $Database set (AllDatabases expansion); the process body reads all of them. Separate
    // hops do not share the begin scope, so carry them forward. The SMO servers are live object
    // references in this runspace - carrying the reference keeps the same open connection.
    private object? _sourceServer;
    private object? _destServer;
    private object? _source;
    private object? _destination;
    private object? _jobOwner;
    private object? _databaseList;

    // Process -> end carrier. $start is Get-Date'd at the top of the source process block and read in
    // the end block's duration message; a per-record hop would reset it, so carry it forward.
    private object? _start;

    // Function-interrupt latch. The source is ONE advanced function whose interrupt flag is
    // function-scoped: a begin validation/connection Stop-Function, or the process "SQL Agent not
    // running" / "Failure getting SQL Agent service" Stop-Function (the non-Continue ones), makes the
    // process block's leading Test-FunctionInterrupt return early AND makes the end block skip its
    // final message. A per-record hop resets that flag, so carry it and gate ProcessRecord/EndProcessing
    // with it (reproduce, not sanitize).
    private bool _interrupted;

    // The process body emits arbitrary result objects, so the process-complete sentinel is keyed on
    // this per-invocation GUID token compared ORDINAL (a property-name/truthiness key could collide).
    private readonly string _processToken = Guid.NewGuid().ToString("N");

    protected override void BeginProcessing()
    {
        // The source Destination parameter defaults to $SqlInstance (a param default that references
        // another parameter). Reproduce it here so the begin body's `if (-not $Destination)` stays the
        // dead branch it is in the source (Destination is already truthy) and DestinationSqlCredential
        // is NOT silently replaced by SqlCredential on the same-server path.
        object? effectiveDestination = MyInvocation.BoundParameters.ContainsKey(nameof(Destination))
            ? (object?)Destination
            : SqlInstance;

        // Begin STREAMS (not buffered): the source begin can emit a Stop-Function warning and then keep
        // going (e.g. Test-DbaPath probe verbose), so streaming forwards emits as produced.
        bool completed = false;
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__RemoveDbaDatabaseSafelyBeginComplete"]?.Value))
            {
                _sourceServer = UnwrapHopValue(item.Properties["SourceServer"]?.Value);
                _destServer = UnwrapHopValue(item.Properties["DestServer"]?.Value);
                _source = UnwrapHopValue(item.Properties["Source"]?.Value);
                _destination = UnwrapHopValue(item.Properties["Destination"]?.Value);
                _jobOwner = UnwrapHopValue(item.Properties["JobOwner"]?.Value);
                _databaseList = UnwrapHopValue(item.Properties["Database"]?.Value);
                _interrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
                completed = true;
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, BeginScript,
            SqlInstance, SqlCredential, effectiveDestination, DestinationSqlCredential, Database,
            AllDatabases.ToBool(), BackupFolder, JobOwner, Force.ToBool(), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
        if (!completed)
            _interrupted = true;
    }

    protected override void ProcessRecord()
    {
        // Source :234 - the function-scoped interrupt latch (from begin, or a prior record's process
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
                item.Properties["__RemoveDbaDatabaseSafelyProcessComplete"]?.Value as string, _processToken, StringComparison.Ordinal))
            {
                _start = UnwrapHopValue(item.Properties["Start"]?.Value);
                _interrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            _sourceServer, _destServer, _source, _destination, _jobOwner, _databaseList,
            SqlInstance, SqlCredential, DestinationSqlCredential, BackupFolder, CategoryName, BackupCompression,
            NoDbccCheckDb.ToBool(), Force.ToBool(), EnableException.ToBool(), this, _processToken,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
    {
        // Source :543 - the end block's leading Test-FunctionInterrupt return: skip the final message
        // when begin or the process block latched the interrupt.
        if (_interrupted || Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, EndScript,
            _start, this,
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
param($SqlInstance, $SqlCredential, $Destination, $DestinationSqlCredential, $Database, $AllDatabases, $BackupFolder, $JobOwner, $Force, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, $SqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Destination, $DestinationSqlCredential, $Database, $AllDatabases, [string]$BackupFolder, $JobOwner, $Force, $EnableException)

    # The begin body has early returns (validation/connection Stop-Function; return); dot-source it so a
    # return exits only this block and the trailing sentinel (carrying the connected servers, resolved
    # database set and Interrupted state) still runs. Test-FunctionInterrupt reads the fixed-name latch
    # variable Stop-Function set in this same scope, so it observes a non-Continue Stop-Function here.
    . {
        $jobowner = $JobOwner
        if ($Force) { $ConfirmPreference = 'none' }

        if (!$AllDatabases -and !$Database) {
            Stop-Function -Message "You must specify at least one database. Use -Database or -AllDatabases." -FunctionName Remove-DbaDatabaseSafely
            return
        }

        try {
            $sourceserver = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -FunctionName Remove-DbaDatabaseSafely
            return
        }

        if (-not $Destination) {
            $Destination = $SqlInstance
            $DestinationSqlCredential = $SqlCredential
        }

        if ($SqlInstance -ne $Destination) {
            try {
                $destserver = Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination -FunctionName Remove-DbaDatabaseSafely
                return
            }

            $sourcenb = $sourceserver.ComputerName
            $destnb = $destserver.ComputerName

            if ($BackupFolder.StartsWith("\\") -eq $false -and $sourcenb -ne $destnb) {
                Stop-Function -Message "Backup folder must be a network share if the source and destination servers are not the same." -Target $backupFolder -FunctionName Remove-DbaDatabaseSafely
                return
            }
        } else {
            $destserver = $sourceserver
        }

        $source = $sourceserver.DomainInstanceName
        $destination = $destserver.DomainInstanceName

        if (!$jobowner) {
            $jobowner = Get-SqlSaLogin -SqlInstance $destserver
        }

        if ($alldatabases -or !$Database) {
            $database = ($sourceserver.databases | Where-Object { $_.IsSystemObject -eq $false -and ($_.Status -match 'Offline') -eq $false }).Name
        }

        if (!(Test-DbaPath -SqlInstance $destserver -Path $backupFolder)) {
            $serviceAccount = $destserver.ServiceAccount
            Stop-Function -Message "Can't access $backupFolder Please check if $serviceAccount has permissions." -Target $backupFolder -FunctionName Remove-DbaDatabaseSafely
            return
        }

        #TODO: Test
        $jobname = "Rationalised Final Database Restore for $dbName"
        $jobStepName = "Restore the $dbName database from Final Backup"

        if (!($destserver.Logins | Where-Object { $_.Name -eq $jobowner })) {
            Stop-Function -Message "$destination does not contain the login $jobowner - Please fix and try again - Aborting." -Target $jobowner -FunctionName Remove-DbaDatabaseSafely
            return
        }
    }
    [pscustomobject]@{ __RemoveDbaDatabaseSafelyBeginComplete = $true; SourceServer = $sourceserver; DestServer = $destserver; Source = $source; Destination = $destination; JobOwner = $jobowner; Database = $Database; Interrupted = [bool](Test-FunctionInterrupt) }
} $SqlInstance $SqlCredential $Destination $DestinationSqlCredential $Database $AllDatabases $BackupFolder $JobOwner $Force $EnableException @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = """
param($sourceserver, $destserver, $source, $destination, $jobowner, $Database, $SqlInstance, $SqlCredential, $DestinationSqlCredential, $BackupFolder, $CategoryName, $BackupCompression, $NoDbccCheckDb, $Force, $EnableException, $__realCmdlet, $__processToken, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param($sourceserver, $destserver, $source, $destination, $jobowner, $Database, [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, $SqlCredential, $DestinationSqlCredential, [string]$BackupFolder, [string]$CategoryName, [string]$BackupCompression, $NoDbccCheckDb, $Force, $EnableException, $__realCmdlet, $__processToken)

    # -Force sets function-scoped $ConfirmPreference='none' in the SOURCE begin, persisting across process
    # records; separate hops don't share that scope, so re-establish it here (carried via $Force).
    if ($Force) { $ConfirmPreference = 'none' }

    # Dot-source so the process body's early returns exit only this block and the trailing sentinel
    # (carrying $start and the interrupt latch) still runs.
    . {
        if (Test-FunctionInterrupt) {
            return
        }

        $start = Get-Date

        try {
            $destInstanceName = $destserver.InstanceName

            if ($destserver.EngineEdition -match "Express") {
                Write-Message -Level Warning -Message "$destInstanceName is Express Edition which does not support SQL Server Agent." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                return
            }

            if ($destInstanceName -eq '') {
                $destInstanceName = "MSSQLSERVER"
            }
            $agentService = Get-DbaService -ComputerName $destserver.ComputerName -InstanceName $destInstanceName -Type Agent -EnableException

            if ($agentService.State -ne 'Running') {
                Stop-Function -Message "SQL Server Agent is not running. Please start the service." -FunctionName Remove-DbaDatabaseSafely
                return
            } else {
                Write-Message -Level Verbose -Message "SQL Server Agent $($agentService.Name) is running." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
            }
        } catch {
            Stop-Function -Message "Failure getting SQL Agent service" -ErrorRecord $_ -FunctionName Remove-DbaDatabaseSafely
            return
        }

        Write-Message -Level Verbose -Message "Starting Rationalisation Script at $start." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"

        foreach ($dbName in $Database) {

            $db = $sourceserver.databases[$dbName]

            # The db check is needed when the number of databases exceeds 255, then it's no longer auto-populated
            if (!$db) {
                Stop-Function -Message "$dbName does not exist on $source. Aborting routine for this database." -Continue -FunctionName Remove-DbaDatabaseSafely
            }

            $lastFullBckDuration = ( Get-DbaDbBackupHistory -SqlInstance $sourceserver -Database $dbName -LastFull).Duration

            if (-NOT ([string]::IsNullOrEmpty($lastFullBckDuration))) {
                $lastFullBckDurationSec = $lastFullBckDuration.TotalSeconds
                $lastFullBckDurationMin = [Math]::Round($lastFullBckDuration.TotalMinutes, 2)

                Write-Message -Level Verbose -Message "From the backup history the last full backup took $lastFullBckDurationSec seconds ($lastFullBckDurationMin minutes)" -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                if ($lastFullBckDurationSec -gt 600) {
                    Write-Message -Level Verbose -Message "Last full backup took more than 10 minutes. Do you want to continue?" -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"

                    # Set up the parts for the user choice
                    $Title = "Backup duration"
                    $Info = "Last full backup took more than $lastFullBckDurationMin minutes. Do you want to continue?"

                    $Options = [System.Management.Automation.Host.ChoiceDescription[]] @("&Yes", "&No (Skip)")
                    [int]$Defaultchoice = 0
                    $choice = $host.UI.PromptForChoice($Title, $Info, $Options, $Defaultchoice)
                    # Check the given option
                    if ($choice -eq 1) {
                        Stop-Function -Message "You have chosen skipping the database $dbName because of last known backup time ($lastFullBckDurationMin minutes)." -Target $dbName -Continue -FunctionName Remove-DbaDatabaseSafely
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Couldn't find last full backup time for database $dbName using Get-DbaDbBackupHistory." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
            }

            $jobname = "Rationalised Database Restore Script for $dbName"
            $jobStepName = "Restore the $dbName database from Final Backup"
            $checkJob = Get-DbaAgentJob -SqlInstance $destserver -Job $jobname

            if ($checkJob.count -gt 0) {
                if ($Force -eq $false) {
                    Stop-Function -Message "FAILED: The Job $jobname already exists. Have you done this before? Rename the existing job and try again or use -Force to drop and recreate." -Continue -FunctionName Remove-DbaDatabaseSafely
                } else {
                    if ($__realCmdlet.ShouldProcess($dbName, "Dropping $jobname on $destination")) {
                        Write-Message -Level Verbose -Message "Dropping $jobname on $destination." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                        $checkJob.Drop()
                    }
                }
            }


            Write-Message -Level Verbose -Message "Starting Rationalisation of $dbName." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
            ## if we want to Dbcc before to abort if we have a corrupt database to start with
            if ($NoDbccCheckDb -eq $false) {
                if ($__realCmdlet.ShouldProcess($dbName, "Running dbcc check on $dbName on $source")) {
                    Write-Message -Level Verbose -Message "Starting DBCC CHECKDB for $dbName on $source." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                    $dbccgood = Start-DbccCheck -server $sourceserver -dbname $dbName -table

                    if ($dbccgood -ne "Success") {
                        if ($Force -eq $false) {
                            Write-Message -Level Verbose -Message "DBCC failed for $dbName (you should check that). Aborting routine for this database." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                            continue
                        } else {
                            Write-Message -Level Verbose -Message "DBCC failed, but Force specified. Continuing." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                        }
                    }
                }
            }

            if ($__realCmdlet.ShouldProcess($source, "Backing up $dbName")) {

                Write-Message -Level Verbose -Message "Starting Backup for $dbName on $source." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                ## Take a Backup
                try {
                    $timenow = [DateTime]::Now.ToString('yyyyMMdd_HHmmss')

                    if ($Force -and $dbccgood -ne "Success") {
                        $filename = "$backupFolder\$($dbName)_DBCCERROR_$timenow.bak"
                    } else {
                        $filename = "$backupFolder\$($dbName)_Final_Before_Drop_$timenow.bak"
                    }

                    $DefaultCompression = $sourceserver.Configuration.DefaultBackupCompression.ConfigValue
                    $backupWithCompressionParams = @{
                        SqlInstance     = $SqlInstance
                        SqlCredential   = $SqlCredential
                        Database        = $dbName
                        BackupFileName  = $filename
                        CompressBackup  = $true
                        Checksum        = $true
                        EnableException = $true
                    }

                    $backupWithoutCompressionParams = @{
                        SqlInstance     = $SqlInstance
                        SqlCredential   = $SqlCredential
                        Database        = $dbName
                        BackupFileName  = $filename
                        Checksum        = $true
                        EnableException = $true
                    }
                    if ($BackupCompression -eq "Default") {
                        if ($DefaultCompression -eq 1) {
                            $null = Backup-DbaDatabase @backupWithCompressionParams
                        } else {
                            $null = Backup-DbaDatabase @backupWithoutCompressionParams
                        }
                    } elseif ($BackupCompression -eq "On") {
                        $null = Backup-DbaDatabase @backupWithCompressionParams
                    } else {
                        $null = Backup-DbaDatabase @backupWithoutCompressionParams
                    }

                } catch {
                    Stop-Function -Message "FAILED : Restore Verify Only failed for $filename on $server - aborting routine for this database. Exception: $_" -Target $filename -ErrorRecord $_ -Continue -FunctionName Remove-DbaDatabaseSafely
                }
            }

            if ($__realCmdlet.ShouldProcess($destination, "Creating Automated Restore Job from Golden Backup for $dbName on $destination")) {
                Write-Message -Level Verbose -Message "Creating Automated Restore Job from Golden Backup for $dbName on $destination." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                try {
                    if ($Force -eq $true -and $dbccgood -ne "Success") {
                        $jobName = $jobname -replace "Rationalised", "DBCC ERROR"
                    }

                    ## Create a Job Category
                    if (!(Get-DbaAgentJobCategory -SqlInstance $destination -SqlCredential $DestinationSqlCredential -Category $categoryname)) {
                        $null = New-DbaAgentJobCategory -SqlInstance $destination -SqlCredential $DestinationSqlCredential -Category $categoryname -EnableException
                    }

                    try {
                        if ($__realCmdlet.ShouldProcess($destination, "Creating Agent Job $jobname on $destination")) {
                            $jobParams = @{
                                SqlInstance     = $destination
                                SqlCredential   = $DestinationSqlCredential
                                Job             = $jobname
                                Category        = $categoryname
                                Description     = "This job will restore the $dbName database using the final backup located at $filename."
                                Owner           = $jobowner
                                EnableException = $true
                            }
                            $job = New-DbaAgentJob @jobParams

                            Write-Message -Level Verbose -Message "Created Agent Job $jobname on $destination." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                        }
                    } catch {
                        Stop-Function -Message "FAILED : To Create Agent Job $jobname on $destination - aborting routine for this database." -Target $categoryname -ErrorRecord $_ -Continue -FunctionName Remove-DbaDatabaseSafely
                    }

                    ## Create Job Step
                    ## Aaron's Suggestion: In the restore script, add a comment block that tells the last known size of each file in the database.
                    ## Suggestion check for disk space before restore
                    ## Create Restore Script
                    try {
                        $jobStepCommand = Restore-DbaDatabase -SqlInstance $destserver -Path $filename -OutputScriptOnly -WithReplace -EnableException

                        $jobStepParams = @{
                            SqlInstance     = $destination
                            SqlCredential   = $DestinationSqlCredential
                            Job             = $job
                            StepName        = $jobStepName
                            SubSystem       = 'TransactSql'
                            Command         = $jobStepCommand
                            Database        = 'master'
                            OnSuccessAction = 'QuitWithSuccess'
                            OnFailAction    = 'QuitWithFailure'
                            StepId          = 1
                            EnableException = $true
                        }
                        if ($__realCmdlet.ShouldProcess($destination, "Creating Agent JobStep on $destination")) {
                            $jobStep = New-DbaAgentJobStep @jobStepParams
                        }
                        $jobStartStepid = $jobStep.ID
                        Write-Message -Level Verbose -Message "Created Agent JobStep $jobStepName on $destination." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                    } catch {
                        Stop-Function -Message "FAILED : To Create Agent JobStep $jobStepName on $destination - Aborting." -Target $jobStepName -ErrorRecord $_ -Continue -FunctionName Remove-DbaDatabaseSafely
                    }
                    if ($__realCmdlet.ShouldProcess($destination, "Applying Agent Job $jobname to $destination")) {
                        $job.StartStepID = $jobStartStepid
                        $job.Alter()
                    }
                } catch {
                    Stop-Function -Message "FAILED : To Create Agent Job $jobname on $destination - aborting routine for $dbName. Exception: $_" -Target $jobname -ErrorRecord $_ -Continue -FunctionName Remove-DbaDatabaseSafely
                }
            }

            if ($__realCmdlet.ShouldProcess($destination, "Dropping Database $dbName on $sourceserver")) {
                ## Drop the database
                try {
                    $null = Remove-DbaDatabase -SqlInstance $sourceserver -Database $dbName -Confirm:$false -EnableException
                    Write-Message -Level Verbose -Message "Dropped $dbName Database on $source prior to running the Agent Job" -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                } catch {
                    Stop-Function -Message "FAILED : To Drop database $dbName on $server - aborting routine for $dbName. Exception: $_" -Continue -FunctionName Remove-DbaDatabaseSafely
                }
            }

            if ($__realCmdlet.ShouldProcess($destination, "Running Agent Job on $destination to restore $dbName")) {
                ## Run the restore job to restore it
                Write-Message -Level Verbose -Message "Starting $jobname on $destination." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                try {
                    $job.Start()
                    $job.Refresh()
                    $status = $job.CurrentRunStatus

                    while ($status -ne 'Idle') {
                        Write-Message -Level Verbose -Message "Restore Job for $dbName on $destination is $status." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                        Start-Sleep -Seconds 15
                        $job.Refresh()
                        $status = $job.CurrentRunStatus
                    }

                    Write-Message -Level Verbose -Message "Restore Job $jobname has completed on $destination." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                    Write-Message -Level Verbose -Message "Sleeping for a few seconds to ensure the next step (DBCC) succeeds." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                    Start-Sleep -Seconds 10 ## This is required to ensure the next DBCC Check succeeds
                } catch {
                    Stop-Function -Message "FAILED : Restore Job $jobname failed on $destination - aborting routine for $dbName. Exception: $_" -Continue -FunctionName Remove-DbaDatabaseSafely
                }

                if ($job.LastRunOutcome -ne 'Succeeded') {
                    # LOL, love the plug.
                    Write-Message -Level Warning -Message "FAILED : Restore Job $jobname failed on $destination - aborting routine for $dbName." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                    Write-Message -Level Warning -Message "Check the Agent Job History on $destination - if you have SSMS2016 July release or later." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                    Write-Message -Level Warning -Message "Get-DbaAgentJobHistory -SqlInstance $destination -Job '$jobname'." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"

                    continue
                }

                $refreshRetries = 1

                $destserver.Databases.Refresh()
                $restoredDatabase = Get-DbaDatabase -SqlInstance $destserver -Database $dbName
                while ($null -eq $restoredDatabase -and $refreshRetries -lt 6) {
                    Write-Message -Level verbose -Message "Database $dbName not found! Refreshing collection." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"

                    #refresh database list, otherwise the next step (DBCC) can fail
                    $restoredDatabase.Parent.Databases.Refresh()

                    Start-Sleep -Seconds 1

                    $refreshRetries += 1
                }
            }

            ## Run a Dbcc No choice here
            if ($__realCmdlet.ShouldProcess($dbName, "Running Dbcc CHECKDB on $dbName on $destination")) {
                Write-Message -Level Verbose -Message "Starting Dbcc CHECKDB for $dbName on $destination." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                $dbccgood = Start-DbccCheck -server $sourceserver -dbname $dbName -table

                if ($dbccgood -ne "Success") {
                    Write-Message -Level Verbose -Message "DBCC CHECKDB finished successfully for $dbName on $servername." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                } else {
                    Write-Message -Level Verbose -Message "DBCC failed for $dbName (you should check that). Continuing." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                }
            }

            if ($__realCmdlet.ShouldProcess($dbName, "Dropping Database $dbName on $destination")) {
                ## Drop the database
                try {
                    $null = Remove-DbaDatabase -SqlInstance $destserver -Database $dbName -Confirm:$false -EnableException
                    Write-Message -Level Verbose -Message "Dropped $dbName database on $destination." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
                } catch {
                    Stop-Function -Message "FAILED : To Drop database $dbName on $destination - Aborting. Exception: $_" -Target $dbName -ErrorRecord $_ -Continue -FunctionName Remove-DbaDatabaseSafely
                }
            }
            Write-Message -Level Verbose -Message "Rationalisation Finished for $dbName." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"

            [PSCustomObject]@{
                SqlInstance     = $source
                DatabaseName    = $dbName
                JobName         = $jobname
                TestingInstance = $destination
                BackupFolder    = $backupFolder
            }
        }
    }
    [pscustomobject]@{ __RemoveDbaDatabaseSafelyProcessComplete = $__processToken; Start = $start; Interrupted = [bool](Test-FunctionInterrupt) }
} $sourceserver $destserver $source $destination $jobowner $Database $SqlInstance $SqlCredential $DestinationSqlCredential $BackupFolder $CategoryName $BackupCompression $NoDbccCheckDb $Force $EnableException $__realCmdlet $__processToken @__commonParameters 3>&1 2>&1
""";

    private const string EndScript = """
param($start, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param($start, $__realCmdlet)
    if ($__realCmdlet.ShouldProcess("console", "Showing final message")) {
        $End = Get-Date
        Write-Message -Level Verbose -Message "Finished at $End." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
        $Duration = $End - $start
        Write-Message -Level Verbose -Message "Script Duration: $Duration." -FunctionName Remove-DbaDatabaseSafely -ModuleName "dbatools"
    }
} $start $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}

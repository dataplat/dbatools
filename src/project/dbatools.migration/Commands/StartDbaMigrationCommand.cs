#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Migrates a whole SQL Server instance - databases, logins, server objects and configuration -
/// from a source to one or more destinations. Port of public/Start-DbaMigration.ps1; the workflow
/// remains a module-scoped PowerShell compatibility hop. Surface pinned by
/// migration/baselines/Start-DbaMigration.json.
///
/// BEGIN+PROCESS+END lifecycle-split. No parameter is pipeline-bound, so process fires exactly
/// once; the split exists because state crosses the three blocks, not because records do.
///
/// BEGIN -&gt; PROCESS CARRY. begin validates the switch combinations, then computes four values the
/// process block reads out of a scope that is gone by the time it runs:
///   $elapsed       - the Stopwatch the end block formats into "Total Elapsed time".
///   $started       - the migration start timestamp, likewise end-block only.
///   $stepCounter   - the progress step number the process block post-increments 22 times.
///   $BackupRestore - begin flips it true when only -UseLastBackup was given. process repeats the
///                    same flip, so the carry is fidelity rather than necessity; carrying it keeps
///                    the two blocks reading one value instead of two that happen to agree.
///
/// PROCESS -&gt; END CARRY. $dacOpened and $sourceServerDac are process locals the end block reads to
/// close the dedicated admin connection. They ride the process sentinel.
///
/// THE INTERRUPT LATCH IS SEEDED, NOT GUARDED. Both later blocks read the flag themselves - process
/// at :324 and end at :633 - so the port has to reproduce the read, and this source is one where
/// the flag genuinely governs: begin's six validation guards are Stop-Function WITHOUT -Continue,
/// and each is followed by a return. Rather than guard ProcessRecord in C#, each hop scope seeds
/// $LATCH_NAME to the carried value before the body runs, so the source's own
/// "if (Test-FunctionInterrupt) { return }" lines stay verbatim and keep working - Stop-Function
/// writes that variable at -Scope 1, which is the same scope the seed lands in. Two things fall out
/// of doing it this way rather than with a C# Interrupted guard. The end block runs its
/// Disconnect-DbaInstance BEFORE it reads the flag, which a top-of-EndProcessing guard would skip,
/// leaking the DAC. And a test that shadows Test-FunctionInterrupt sees its shadow called, exactly
/// as the function world does.
///
/// -WhatIf AND -Confirm ARE CARRIED INTO THE PROCESS HOP, not just routed through $__realCmdlet.
/// Only the SysDbUserObjects step consults $PSCmdlet.ShouldProcess directly; every other step is a
/// bare call to a Copy-Dba* command that declares its own SupportsShouldProcess and, in the function
/// world, inherited $WhatIfPreference from the caller's scope. A hop scope does not inherit it, so
/// without this carry "Start-DbaMigration -WhatIf" performed a real migration - measured, not
/// inferred: the suite's -WhatIf leg passed against the script function and failed against the
/// cmdlet by finding the database actually copied to the destination. Splatting the bound values
/// into the hop's [CmdletBinding(SupportsShouldProcess)] block reproduces the inheritance.
///
/// $ConfirmPreference IS SET IN BOTH HOPS. begin's "if ($Force) { $ConfirmPreference = 'none' }"
/// suppresses a prompt raised by the ShouldProcess call in the PROCESS block, which in the function
/// world shares begin's scope. The hop scopes do not, so the assignment is repeated in the process
/// hop; without it -Force would stop suppressing the gate.
///
/// NAMED-WRAPPER SHIM. The body calls Write-ProgressHelper 22 times and that helper derives its
/// activity string from (Get-PSCallStack)[1].Command, which reads as a scriptblock marker when the
/// body runs bare. The process body therefore runs inside a function carrying the command's name,
/// dot-invoked so its locals stay in the enclosing scope for the sentinel to read and its early
/// returns exit only the body.
///
/// Switches marshal as real booleans and the inner param leaves them untyped: PowerShell excludes
/// [switch] parameters from positional binding, so one typed flag would shift every argument after
/// it. The body reads them as booleans and splices them with -Switch:$Value, which a boolean serves.
/// </summary>
[Cmdlet(VerbsLifecycle.Start, "DbaMigration", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class StartDbaMigrationCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance to migrate from.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter? Source { get; set; }

    /// <summary>One or more destination SQL Server instances to migrate to.</summary>
    [Parameter(Position = 1)]
    public DbaInstanceParameter[]? Destination { get; set; }

    /// <summary>Windows credentials used to decrypt passwords over PowerShell remoting.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    /// <summary>Migrate databases by detaching, copying the files and reattaching.</summary>
    [Parameter]
    public SwitchParameter DetachAttach { get; set; }

    /// <summary>Reattach the databases at the source once a detach/attach migration finishes.</summary>
    [Parameter]
    public SwitchParameter Reattach { get; set; }

    /// <summary>Migrate databases with copy-only backups and restores.</summary>
    [Parameter]
    public SwitchParameter BackupRestore { get; set; }

    /// <summary>Network share or Azure Storage URL that holds the migration backups.</summary>
    [Parameter(Position = 3, HelpMessage = @"Specify a valid network share in the format \\server\share that can be accessed by your account and both Sql Server service accounts, or a URL to an Azure Storage account")]
    public string? SharedPath { get; set; }

    /// <summary>Overwrite destination databases of the same name.</summary>
    [Parameter]
    public SwitchParameter WithReplace { get; set; }

    /// <summary>Leave the restored databases in a restoring state.</summary>
    [Parameter]
    public SwitchParameter NoRecovery { get; set; }

    /// <summary>Set the source databases read-only before the migration starts.</summary>
    [Parameter]
    public SwitchParameter SetSourceReadOnly { get; set; }

    /// <summary>Set the source databases offline before the migration starts.</summary>
    [Parameter]
    public SwitchParameter SetSourceOffline { get; set; }

    /// <summary>Restore the databases to the source server's own file paths.</summary>
    [Parameter]
    public SwitchParameter ReuseSourceFolderStructure { get; set; }

    /// <summary>Include ReportServer, ReportServerTempDB, SSISDB and distribution databases.</summary>
    [Parameter]
    public SwitchParameter IncludeSupportDbs { get; set; }

    /// <summary>Login to the source instance using alternative credentials.</summary>
    [Parameter(Position = 4)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>Login to the destination instances using alternative credentials.</summary>
    [Parameter(Position = 5)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Migration components to skip.</summary>
    [Parameter(Position = 6)]
    [ValidateSet("Databases", "Logins", "AgentServer", "Credentials", "LinkedServers", "SpConfigure",
        "CentralManagementServer", "DatabaseMail", "SysDbUserObjects", "SystemTriggers", "BackupDevices",
        "Audits", "Endpoints", "ExtendedEvents", "PolicyManagement", "ResourceGovernor",
        "ServerAuditSpecifications", "CustomErrors", "ServerRoles", "DataCollector", "StartupProcedures",
        "ExtendedStoredProcedures", "AgentServerProperties", "MasterCertificates", "SsisCatalog")]
    public string[]? Exclude { get; set; }

    /// <summary>Disable the migrated Agent jobs on the destination.</summary>
    [Parameter]
    public SwitchParameter DisableJobsOnDestination { get; set; }

    /// <summary>Disable the Agent jobs on the source once they are migrated.</summary>
    [Parameter]
    public SwitchParameter DisableJobsOnSource { get; set; }

    /// <summary>Leave the destination sa login name alone.</summary>
    [Parameter]
    public SwitchParameter ExcludeSaRename { get; set; }

    /// <summary>Restore from the databases' existing last backups instead of taking new ones.</summary>
    [Parameter]
    public SwitchParameter UseLastBackup { get; set; }

    /// <summary>Preserve Change Data Capture settings through the restore.</summary>
    [Parameter]
    public SwitchParameter KeepCDC { get; set; }

    /// <summary>Preserve replication settings through the restore.</summary>
    [Parameter]
    public SwitchParameter KeepReplication { get; set; }

    /// <summary>Continue an interrupted restore from the existing backup chain.</summary>
    [Parameter]
    public SwitchParameter Continue { get; set; }

    /// <summary>Migrate credentials, mail accounts and linked servers without their passwords.</summary>
    [Parameter]
    public SwitchParameter ExcludePassword { get; set; }

    /// <summary>Drop and recreate destination objects that already exist.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>Name of the SQL Server credential that reaches the Azure Storage account.</summary>
    [Parameter(Position = 7)]
    public string? AzureCredential { get; set; }

    /// <summary>Password for the destination database master key created during certificate migration.</summary>
    [Parameter(Position = 8)]
    public System.Security.SecureString? MasterKeyPassword { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // begin's $elapsed, $started, $stepCounter, the resolved $BackupRestore, and the latch.
    private Hashtable? _beginState;
    // process's $dacOpened and $sourceServerDac, which the end block closes, plus the latch.
    private Hashtable? _processState;

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Destination, Exclude, SharedPath, DetachAttach.ToBool(), Reattach.ToBool(),
            BackupRestore.ToBool(), UseLastBackup.ToBool(), Continue.ToBool(), Force.ToBool(),
            EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__startDbaMigrationBegin"))
            {
                _beginState = sentinel["__startDbaMigrationBegin"] as Hashtable;
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    // NO Interrupted PROLOGUE. The latch begin may have set is seeded into the process hop's scope
    // instead, so the source's own "if (Test-FunctionInterrupt) { return }" performs the stop and
    // the process sentinel still reaches EndProcessing, which needs $dacOpened either way.
    protected override void ProcessRecord()
    {
        // Streaming, not buffered: a migration copies databases over many minutes and emits a
        // result object per copied database, so a buffered hop would withhold every completed copy
        // until the whole instance finished.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__startDbaMigrationProcess"))
            {
                _processState = sentinel["__startDbaMigrationProcess"] as Hashtable;
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            Source, SourceSqlCredential, Destination, DestinationSqlCredential, Credential,
            DetachAttach.ToBool(), Reattach.ToBool(), BackupRestore.ToBool(), SharedPath,
            WithReplace.ToBool(), NoRecovery.ToBool(), SetSourceReadOnly.ToBool(), SetSourceOffline.ToBool(),
            ReuseSourceFolderStructure.ToBool(), IncludeSupportDbs.ToBool(), Exclude,
            DisableJobsOnDestination.ToBool(), DisableJobsOnSource.ToBool(), ExcludeSaRename.ToBool(),
            UseLastBackup.ToBool(), KeepCDC.ToBool(), KeepReplication.ToBool(), Continue.ToBool(),
            ExcludePassword.ToBool(), Force.ToBool(), AzureCredential, MasterKeyPassword,
            EnableException.ToBool(), _beginState, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // NOT guarded. The source's end block closes the dedicated admin connection BEFORE it reads the
    // interrupt flag, so a guard here would leak the DAC on exactly the runs that failed.
    protected override void EndProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, EndScript,
            _beginState, _processState, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
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

    // PS: the begin block VERBATIM inside a dot-sourced wrapper, so its six early returns exit only
    // the body and the sentinel below still reports what the guards left behind.
    private const string BeginScript = """
param($Destination, $Exclude, $SharedPath, $DetachAttach, $Reattach, $BackupRestore, $UseLastBackup, $Continue, $Force, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, [string[]]$Exclude, [string]$SharedPath, $DetachAttach, $Reattach, $BackupRestore, $UseLastBackup, $Continue, $Force, $EnableException, $__boundVerbose, $__boundDebug)

    . {
        if ($Force) { $ConfirmPreference = 'none' }

        if ($Exclude -notcontains "Databases") {
            if (-not $BackupRestore -and -not $DetachAttach -and -not $UseLastBackup) {
                Stop-Function -Message "You must specify a database migration method (-BackupRestore or -DetachAttach) or -Exclude Databases" -FunctionName Start-DbaMigration
                return
            }
        }
        if ($DetachAttach -and ($BackupRestore -or $UseLastBackup)) {
            Stop-Function -Message "-DetachAttach cannot be used with -BackupRestore or -UseLastBackup" -FunctionName Start-DbaMigration
            return
        }
        if ($BackupRestore -and (-not $SharedPath -and -not $UseLastBackup)) {
            Stop-Function -Message "When using -BackupRestore, you must specify -SharedPath or -UseLastBackup" -FunctionName Start-DbaMigration
            return
        }
        if ($SharedPath -and $UseLastBackup) {
            Stop-Function -Message "-SharedPath cannot be used with -UseLastBackup because the backup path is determined by the paths in the last backups" -FunctionName Start-DbaMigration
            return
        }
        if ($DetachAttach -and -not $Reattach -and $Destination.Count -gt 1) {
            Stop-Function -Message "When using -DetachAttach with multiple servers, you must specify -Reattach to reattach database at source" -FunctionName Start-DbaMigration
            return
        }
        if ($Continue -and -not $UseLastBackup) {
            Stop-Function -Message "-Continue cannot be used without -UseLastBackup" -FunctionName Start-DbaMigration
            return
        }
        if ($UseLastBackup -and -not $BackupRestore) {
            $BackupRestore = $true
        }

        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        $started = Get-Date
        $stepCounter = 0
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __startDbaMigrationBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value); Elapsed = $elapsed; Started = $started; StepCounter = $stepCounter; BackupRestore = $BackupRestore } }
} $Destination $Exclude $SharedPath $DetachAttach $Reattach $BackupRestore $UseLastBackup $Continue $Force $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM inside the named-wrapper shim. Edits: -FunctionName
    // Start-DbaMigration (plus -ModuleName "dbatools" on Write-Message) on every direct call, and
    // $Pscmdlet -> $__realCmdlet so the gate reaches the compiled cmdlet's own ShouldProcess.
    private const string ProcessScript = """
param($Source, $SourceSqlCredential, $Destination, $DestinationSqlCredential, $Credential, $DetachAttach, $Reattach, $BackupRestore, $SharedPath, $WithReplace, $NoRecovery, $SetSourceReadOnly, $SetSourceOffline, $ReuseSourceFolderStructure, $IncludeSupportDbs, $Exclude, $DisableJobsOnDestination, $DisableJobsOnSource, $ExcludeSaRename, $UseLastBackup, $KeepCDC, $KeepReplication, $Continue, $ExcludePassword, $Force, $AzureCredential, $MasterKeyPassword, $EnableException, $__beginState, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, [PSCredential]$SourceSqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, [PSCredential]$DestinationSqlCredential, [PSCredential]$Credential, $DetachAttach, $Reattach, $BackupRestore, [string]$SharedPath, $WithReplace, $NoRecovery, $SetSourceReadOnly, $SetSourceOffline, $ReuseSourceFolderStructure, $IncludeSupportDbs, [string[]]$Exclude, $DisableJobsOnDestination, $DisableJobsOnSource, $ExcludeSaRename, $UseLastBackup, $KeepCDC, $KeepReplication, $Continue, $ExcludePassword, $Force, [string]$AzureCredential, [Security.SecureString]$MasterKeyPassword, $EnableException, $__beginState, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)

    # begin's once-computed state
    $elapsed = $__beginState.Elapsed
    $started = $__beginState.Started
    $stepCounter = $__beginState.StepCounter
    $BackupRestore = $__beginState.BackupRestore

    # begin set this in the scope the ShouldProcess call below reads; the hop scopes are separate.
    if ($Force) { $ConfirmPreference = 'none' }

    Set-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Value ([bool]$__beginState.Interrupted) -Scope 0

    function Start-DbaMigration {
        if (Test-FunctionInterrupt) { return }

        # testing twice for whatif reasons
        if ($Exclude -notcontains "Databases") {
            if (-not $BackupRestore -and -not $DetachAttach -and -not $UseLastBackup) {
                Stop-Function -Message "You must specify a database migration method (-BackupRestore or -DetachAttach) or -Exclude Databases" -FunctionName Start-DbaMigration
                return
            }
        }

        if ($DetachAttach -and ($BackupRestore -or $UseLastBackup)) {
            Stop-Function -Message "-DetachAttach cannot be used with -BackupRestore or -UseLastBackup" -FunctionName Start-DbaMigration
            return
        }
        if ($BackupRestore -and (-not $SharedPath -and -not $UseLastBackup)) {
            Stop-Function -Message "When using -BackupRestore, you must specify -SharedPath or -UseLastBackup" -FunctionName Start-DbaMigration
            return
        }
        if ($SharedPath -like 'https*' -and $DetachAttach) {
            Stop-Function -Message "URL shared storage is only supported by BackupRstore" -FunctionName Start-DbaMigration
            return
        }
        if ($SharedPath -and $UseLastBackup) {
            Stop-Function -Message "-SharedPath cannot be used with -UseLastBackup because the backup path is determined by the paths in the last backups" -FunctionName Start-DbaMigration
            return
        }
        if ($DetachAttach -and -not $Reattach -and $Destination.Count -gt 1) {
            Stop-Function -Message "When using -DetachAttach with multiple servers, you must specify -Reattach to reattach database at source" -FunctionName Start-DbaMigration
            return
        }
        if ($Continue -and -not $UseLastBackup) {
            Stop-Function -Message "-Continue cannot be used without -UseLastBackup" -FunctionName Start-DbaMigration
            return
        }
        if ($UseLastBackup -and -not $BackupRestore) {
            $BackupRestore = $true
        }

        try {
            # Do we need a dedicated admin connection to the source for password retrieval?
            # If not all of the three are excluded, we do
            $dacNeeded = $Exclude -notcontains 'Credentials' -or $Exclude -notcontains 'DatabaseMail' -or $Exclude -notcontains 'LinkedServers'
            # If passwords are excluded, we don't need a DAC
            if ($ExcludePassword) { $dacNeeded = $false }

            # Do we have a dedicated admin connection already?
            $dacConnected = $Source.Type -eq "Server" -and $Source.InputObject.ConnectionContext.ServerInstance -match "^ADMIN:"

            $dacOpened = $false
            if ($dacNeeded) {
                if ($dacConnected) {
                    Write-Message -Level Verbose -Message "Reusing dedicated admin connection for password retrieval." -FunctionName Start-DbaMigration -ModuleName "dbatools"
                    $sourceServerDac = $Source.InputObject
                    # Reconnect without DAC for Copy-DbaDatabase
                    Write-Message -Level Verbose -Message "Opening additional normal connection for all commands that don't require DAC." -FunctionName Start-DbaMigration -ModuleName "dbatools"
                    $sourceServer = Connect-DbaInstance -SqlInstance $Source.FullName -SqlCredential $SourceSqlCredential
                } else {
                    Write-Message -Level Verbose -Message "Opening dedicated admin connection for password retrieval." -FunctionName Start-DbaMigration -ModuleName "dbatools"
                    $sourceServerDac = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -DedicatedAdminConnection -WarningAction SilentlyContinue
                    if (-not $sourceServerDac) {
                        Stop-Function -Message "Could not establish dedicated admin connection to $Source. Use -ExcludePassword to skip password migration." -Category ConnectionError -Target $Source -FunctionName Start-DbaMigration
                        return
                    }
                    $dacOpened = $true
                    Write-Message -Level Verbose -Message "Opening or reusing additional normal connection for all commands that don't require DAC." -FunctionName Start-DbaMigration -ModuleName "dbatools"
                    $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
                }
            } else {
                if ($dacConnected) {
                    # Reconnect without DAC for Copy-DbaDatabase
                    Write-Message -Level Verbose -Message "Opening additional normal connection for all commands that don't require DAC." -FunctionName Start-DbaMigration -ModuleName "dbatools"
                    $sourceServer = Connect-DbaInstance -SqlInstance $Source.FullName -SqlCredential $SourceSqlCredential
                } else {
                    Write-Message -Level Verbose -Message "Opening or reusing normal connection for all commands that don't require DAC." -FunctionName Start-DbaMigration -ModuleName "dbatools"
                    $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
                }
            }
            if (-not $sourceServer) {
                Stop-Function -Message "Could not connect to source instance $Source." -Category ConnectionError -Target $Source -FunctionName Start-DbaMigration
                return
            }
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source -FunctionName Start-DbaMigration
            return
        }

        if ($Exclude -notcontains 'SpConfigure') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating SQL Server Configuration"
            Write-Message -Level Verbose -Message "Migrating SQL Server Configuration" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            Copy-DbaSpConfigure -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential
        }

        if ($Exclude -notcontains 'MasterCertificates') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Copying certificates in the master database"
            Write-Message -Level Verbose -Message "Copying certificates in the master database" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            Copy-DbaDbCertificate -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -EncryptionPassword (Get-RandomPassword) -MasterKeyPassword $MasterKeyPassword -Database master -SharedPath $SharedPath

        }

        if ($Exclude -notcontains 'CustomErrors') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating custom errors (user defined messages)"
            Write-Message -Level Verbose -Message "Migrating custom errors (user defined messages)" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            Copy-DbaCustomError -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'ServerRoles') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating server roles"
            Write-Message -Level Verbose -Message "Migrating server roles" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            Copy-DbaServerRole -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'Credentials') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating SQL credentials"
            Write-Message -Level Verbose -Message "Migrating SQL credentials" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            if ($dacNeeded) {
                Copy-DbaCredential -Source $sourceServerDac -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Credential $Credential -ExcludePassword:$ExcludePassword -Force:$Force
            } else {
                Copy-DbaCredential -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Credential $Credential -ExcludePassword:$ExcludePassword -Force:$Force
            }
        }

        if ($Exclude -notcontains 'DatabaseMail') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating database mail"
            Write-Message -Level Verbose -Message "Migrating database mail" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            if ($dacNeeded) {
                Copy-DbaDbMail -Source $sourceServerDac -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Credential $Credential -ExcludePassword:$ExcludePassword -Force:$Force
            } else {
                Copy-DbaDbMail -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Credential $Credential -ExcludePassword:$ExcludePassword -Force:$Force
            }
        }

        if ($Exclude -notcontains 'CentralManagementServer') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Central Management Server"
            Write-Message -Level Verbose -Message "Migrating Central Management Server" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            Copy-DbaRegServer -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'BackupDevices') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Backup Devices"
            Write-Message -Level Verbose -Message "Migrating Backup Devices" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            Copy-DbaBackupDevice -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'SystemTriggers') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating System Triggers"
            Write-Message -Level Verbose -Message "Migrating System Triggers" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            Copy-DbaInstanceTrigger -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'Databases') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating databases"
            Write-Message -Level Verbose -Message "Migrating databases" -FunctionName Start-DbaMigration -ModuleName "dbatools"

            $CopyDatabaseSplat = @{
                Source                     = $sourceserver
                Destination                = $Destination
                DestinationSqlCredential   = $DestinationSqlCredential
                SetSourceReadOnly          = $SetSourceReadOnly
                SetSourceOffline           = $SetSourceOffline
                ReuseSourceFolderStructure = $ReuseSourceFolderStructure
                AllDatabases               = $true
                Force                      = $Force
                IncludeSupportDbs          = $IncludeSupportDbs
            }

            if ($BackupRestore) {
                $CopyDatabaseSplat += @{
                    BackupRestore   = $true
                    NoRecovery      = $NoRecovery
                    WithReplace     = $WithReplace
                    KeepCDC         = $KeepCDC
                    KeepReplication = $KeepReplication
                }
                if ($UseLastBackup) {
                    $CopyDatabaseSplat += @{
                        UseLastBackup = $UseLastBackup
                        Continue      = $Continue
                    }
                } else {
                    $CopyDatabaseSplat += @{
                        SharedPath      = $SharedPath
                        AzureCredential = $AzureCredential
                    }
                }
            } else {
                $CopyDatabaseSplat += @{
                    DetachAttach = $DetachAttach
                    Reattach     = $Reattach
                }
            }

            Copy-DbaDatabase @CopyDatabaseSplat | ForEach-Object {
                $PSItem
            }
        }

        if ($Exclude -notcontains 'Logins') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating logins"
            Write-Message -Level Verbose -Message "Migrating logins" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            $syncit = $ExcludeSaRename -eq $false
            Copy-DbaLogin -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force -SyncSaName:$syncit
        }

        if ($Exclude -notcontains 'Logins' -and $Exclude -notcontains 'Databases' -and -not $NoRecovery) {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Updating database owners to match newly migrated logins"
            Write-Message -Level Verbose -Message "Updating database owners to match newly migrated logins" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            foreach ($dest in $Destination) {
                $null = Update-SqlDbOwner -Source $sourceserver -Destination $dest -DestinationSqlCredential $DestinationSqlCredential
            }
        }

        if ($Exclude -notcontains 'LinkedServers') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating linked servers"
            Write-Message -Level Verbose -Message "Migrating linked servers" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            if ($dacNeeded) {
                Copy-DbaLinkedServer -Source $sourceServerDac -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Credential $Credential -ExcludePassword:$ExcludePassword -Force:$Force
            } else {
                Copy-DbaLinkedServer -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Credential $Credential -ExcludePassword:$ExcludePassword -Force:$Force
            }
        }

        if ($Exclude -notcontains 'DataCollector') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Data Collector collection sets"
            Write-Message -Level Verbose -Message "Migrating Data Collector collection sets" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            Copy-DbaDataCollector -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'Audits') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Audits"
            Write-Message -Level Verbose -Message "Migrating Audits" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            Copy-DbaInstanceAudit -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'ServerAuditSpecifications') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Server Audit Specifications"
            Write-Message -Level Verbose -Message "Migrating Server Audit Specifications" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            Copy-DbaInstanceAuditSpecification -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'Endpoints') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Endpoints"
            Write-Message -Level Verbose -Message "Migrating Endpoints" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            Copy-DbaEndpoint -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'PolicyManagement') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Policy Management"
            Write-Message -Level Verbose -Message "Migrating Policy Management" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            Copy-DbaPolicyManagement -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'ResourceGovernor') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Resource Governor"
            Write-Message -Level Verbose -Message "Migrating Resource Governor" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            Copy-DbaResourceGovernor -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'SysDbUserObjects') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating user objects in system databases (this can take a second)"
            Write-Message -Level Verbose -Message "Migrating user objects in system databases (this can take a second)." -FunctionName Start-DbaMigration -ModuleName "dbatools"
            If ($__realCmdlet.ShouldProcess($destination, "Copying user objects.")) {
                Copy-DbaSystemDbUserObject -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$force
            }
        }

        if ($Exclude -notcontains 'ExtendedEvents') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Extended Events"
            Write-Message -Level Verbose -Message "Migrating Extended Events" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            Copy-DbaXESession -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'AgentServer') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating job server"
            Write-Message -Level Verbose -Message "Migrating job server" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            $ExcludeAgentServerProperties = $Exclude -contains 'AgentServerProperties'
            Copy-DbaAgentServer -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -DisableJobsOnDestination:$DisableJobsOnDestination -DisableJobsOnSource:$DisableJobsOnSource -Force:$Force -ExcludeServerProperties:$ExcludeAgentServerProperties
        }

        if ($Exclude -notcontains 'StartupProcedures') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating startup procedures"
            Write-Message -Level Verbose -Message "Migrating startup procedures" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            Copy-DbaStartupProcedure -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential
        }

        if ($Exclude -notcontains 'ExtendedStoredProcedures') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Extended Stored Procedures"
            Write-Message -Level Verbose -Message "Migrating Extended Stored Procedures" -FunctionName Start-DbaMigration -ModuleName "dbatools"
            Copy-DbaExtendedStoredProcedure -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential
        }

        if ($Exclude -notcontains "SsisCatalog") {
            $sourceHasSsisCatalog = $sourceServer.VersionMajor -ge 11
            if ($sourceHasSsisCatalog) {
                $sourceHasSsisCatalog = $null -ne $sourceServer.Databases["SSISDB"]
            }

            if ($sourceHasSsisCatalog) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating SSIS catalog"
                Write-Message -Level Verbose -Message "Migrating SSIS catalog" -FunctionName Start-DbaMigration -ModuleName "dbatools"
                Copy-DbaSsisCatalog -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
            } else {
                Write-Message -Level Verbose -Message "Skipping SSIS catalog migration because the source instance does not have an SSISDB catalog." -FunctionName Start-DbaMigration -ModuleName "dbatools"
            }
        }
    }
    . Start-DbaMigration

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __startDbaMigrationProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value); DacOpened = $dacOpened; SourceServerDac = $sourceServerDac } }
} $Source $SourceSqlCredential $Destination $DestinationSqlCredential $Credential $DetachAttach $Reattach $BackupRestore $SharedPath $WithReplace $NoRecovery $SetSourceReadOnly $SetSourceOffline $ReuseSourceFolderStructure $IncludeSupportDbs $Exclude $DisableJobsOnDestination $DisableJobsOnSource $ExcludeSaRename $UseLastBackup $KeepCDC $KeepReplication $Continue $ExcludePassword $Force $AzureCredential $MasterKeyPassword $EnableException $__beginState $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM, with begin's stopwatch and start timestamp, process's DAC state
    // and process's latch restored ahead of it.
    private const string EndScript = """
param($__beginState, $__processState, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__beginState, $__processState, $EnableException, $__boundVerbose, $__boundDebug)

    # begin's and process's once-computed state
    $elapsed = $__beginState.Elapsed
    $started = $__beginState.Started
    $dacOpened = $__processState.DacOpened
    $sourceServerDac = $__processState.SourceServerDac

    Set-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Value ([bool]$__processState.Interrupted) -Scope 0

        if ($dacOpened) {
            $null = $sourceServerDac | Disconnect-DbaInstance -WhatIf:$false
        }
        if (Test-FunctionInterrupt) { return }
        $totaltime = ($elapsed.Elapsed.toString().Split(".")[0])
        Write-Message -Level Verbose -Message "SQL Server migration complete." -FunctionName Start-DbaMigration -ModuleName "dbatools"
        Write-Message -Level Verbose -Message "Migration started: $started" -FunctionName Start-DbaMigration -ModuleName "dbatools"
        Write-Message -Level Verbose -Message "Migration completed: $(Get-Date)" -FunctionName Start-DbaMigration -ModuleName "dbatools"
        Write-Message -Level Verbose -Message "Total Elapsed time: $totaltime" -FunctionName Start-DbaMigration -ModuleName "dbatools"
} $__beginState $__processState $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

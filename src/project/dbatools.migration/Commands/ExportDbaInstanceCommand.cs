#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports a whole SQL Server instance configuration as T-SQL script files. Port of
/// public/Export-DbaInstance.ps1; the workflow remains a module-scoped PowerShell compatibility
/// hop. Surface pinned by migration/baselines/Export-DbaInstance.json.
///
/// BEGIN+PROCESS+END lifecycle-split. $SqlInstance is ValueFromPipeline, so process fires per piped
/// record and the source's begin/end blocks each run exactly once. No SupportsShouldProcess (plain
/// CmdletBinding), so there is no gate and no $__realCmdlet.
///
/// BEGIN -> PROCESS/END CARRY. begin computes five values the later blocks read, and its scope dies
/// before either runs, so they ride the begin sentinel and a C# Hashtable field:
///   $ScriptingOption - begin materialises New-DbaScriptingOption when the caller omitted one. The
///     SAME object must reach every record; a per-record New- would hand each piped instance a
///     different options object.
///   $eol             - [Environment]::NewLine, read by the server-trigger rewrite and the policy
///     management script builder.
///   $elapsed         - the Stopwatch the end block formats into "Total Elapsed time".
///   $started         - the export start timestamp, likewise end-block only.
///   the resolved $Path and $BatchSeparator - see the bind-time defaults below.
///
/// BIND-TIME DEFAULTS. "$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport')" and
/// "$BatchSeparator = (Get-DbatoolsConfigValue -FullName 'formatting.batchseparator')" are config
/// lookups a C# property initializer cannot express (and DEF-007 forbids anyway). Both resolve ONCE
/// in the begin hop when the caller omitted the parameter - begin already needs $Path for
/// Test-ExportDirectory - and the resolved values carry to process. Bind-once, matching the source.
///
/// INTERRUPT CARRIES ON THE PROCESS AXIS ONLY.
///   process -> process: the export catch at :318 is a Stop-Function WITHOUT -Continue followed by
///     a return, so it latches, and process opens with "if (Test-FunctionInterrupt) { return }" at
///     :272 - a failed New-Item on one record silences every later record. The hop scope dies per
///     record, so the process hop reads the latch at Scope 0 after its body and carries it; the
///     _interrupted field persists it across ProcessRecord calls.
///   begin -> process: NOT carried, because the source cannot latch there. begin's only failure
///     path is Test-ExportDirectory's own Stop-Function, and Stop-Function sets the latch at
///     -Scope 1 relative to ITSELF - that is Test-ExportDirectory's scope, not the caller's - so it
///     dies with the helper. The begin sentinel still reports the latch it reads, which is always
///     false today; that keeps the carrier honest if a direct Stop-Function is ever added to begin.
///   end: NOT guarded. The source's end block carries no Test-FunctionInterrupt, so guarding
///     EndProcessing would suppress the elapsed-time verbose lines the function world always emits.
///
/// NAMED-WRAPPER SHIM. The body calls Write-ProgressHelper 22 times, and that helper derives both
/// its activity string and its step total from (Get-PSCallStack)[1].Command. Run bare in the hop's
/// anonymous scriptblock the caller frame reads as a scriptblock marker, which drops the activity to
/// "Executing &lt;ScriptBlock&gt;". The process body therefore runs inside a function carrying the
/// command's name, dot-invoked so the body's locals, the interrupt latch and the two early returns
/// all behave as they do in the function world. The helper's $instance interpolation resolves the
/// same way, through the dot-sourced scope.
///
/// Get-ExportedFileInfo is declared in the source's begin block and called only from process. A
/// function declaration carries no per-record state, so it is declared in the process hop instead of
/// marshalled; its own Stop-Function and Write-Message stay unattributed, because calls inside a
/// re-declared named helper take no -FunctionName.
///
/// NO OTHER CROSS-RECORD STATE. Every process local - $stepCounter, $server, $dacOpened, $dacNeeded,
/// $dacConnected, $exportPath, $timeNow, $copyDbKeyExports, $outputFilePath, $outputFile, $triggers,
/// $scriptText, $policyObjects, $sysDbUserObjects, $splatDbCert, $splatMasterKey,
/// $databaseCertificates, $databaseMasterKeys - is assigned before it is read inside its own
/// instance iteration, so none can serve a stale value from an earlier record.
///
/// Switches marshal as real booleans and the inner param leaves them untyped: PowerShell excludes
/// [switch] parameters from positional binding, so one typed flag would shift every argument after
/// it. The body reads them as booleans and splices them with -Switch:$Value, which a boolean serves.
/// </summary>
[Cmdlet(VerbsData.Export, "DbaInstance")]
public sealed class ExportDbaInstanceCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Alternative Windows credentials for exporting linked servers and credentials.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    /// <summary>Root directory for the timestamped export folder; defaults to the Path.DbatoolsExport config.</summary>
    [Parameter(Position = 3)]
    [Alias("FilePath")]
    public string? Path { get; set; }

    /// <summary>Generate the database restore scripts with NORECOVERY.</summary>
    [Parameter]
    public SwitchParameter NoRecovery { get; set; }

    /// <summary>The Azure storage credential name used by the generated restore scripts.</summary>
    [Parameter(Position = 4)]
    public string? AzureCredential { get; set; }

    /// <summary>Export database certificates and database master keys alongside the scripts.</summary>
    [Parameter]
    public SwitchParameter IncludeDbMasterKey { get; set; }

    /// <summary>Password used to encrypt exported private keys and master key backups.</summary>
    [Parameter(Position = 5)]
    public System.Security.SecureString? EncryptionPassword { get; set; }

    /// <summary>Password that decrypts a certificate's existing private key before it is re-encrypted.</summary>
    [Parameter(Position = 6)]
    public System.Security.SecureString? DecryptionPassword { get; set; }

    /// <summary>Object types to skip.</summary>
    [Parameter(Position = 7)]
    [ValidateSet("AgentServer", "Audits", "AvailabilityGroups", "BackupDevices", "CentralManagementServer",
        "Credentials", "CustomErrors", "DatabaseMail", "Databases", "DbCertificates", "Endpoints",
        "ExtendedEvents", "LinkedServers", "Logins", "PolicyManagement", "ReplicationSettings",
        "ResourceGovernor", "ServerAuditSpecifications", "ServerRoles", "SpConfigure", "SysDbUserObjects",
        "SystemTriggers", "OleDbProvider")]
    public string[]? Exclude { get; set; }

    /// <summary>The T-SQL batch separator for the generated scripts; defaults to the formatting.batchseparator config.</summary>
    [Parameter(Position = 8)]
    public string? BatchSeparator { get; set; }

    /// <summary>Scripting options object handed to every Export-DbaScript call.</summary>
    [Parameter(Position = 9)]
    public Microsoft.SqlServer.Management.Smo.ScriptingOptions? ScriptingOption { get; set; }

    /// <summary>Omit the header comments from the generated scripts.</summary>
    [Parameter]
    public SwitchParameter NoPrefix { get; set; }

    /// <summary>Replace passwords in the exported scripts with placeholder text.</summary>
    [Parameter]
    public SwitchParameter ExcludePassword { get; set; }

    /// <summary>Overwrite an existing export and drop the timestamp from the folder name.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // begin's $ScriptingOption, $eol, $elapsed, $started and the resolved $Path/$BatchSeparator.
    private Hashtable? _beginState;
    // a process Failure on an earlier record silences later records (source :272 reads the latch).
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Path, BatchSeparator, ScriptingOption, EnableException.ToBool(),
            MyInvocation.BoundParameters.ContainsKey("Path"),
            MyInvocation.BoundParameters.ContainsKey("BatchSeparator"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__exportDbaInstanceBegin"))
            {
                if (sentinel["__exportDbaInstanceBegin"] is Hashtable state)
                {
                    _beginState = state;
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                }
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

    protected override void ProcessRecord()
    {
        if (Interrupted || _interrupted)
        {
            return;
        }

        // Streaming, not buffered: the export writes real files and emits a FileInfo per step over
        // minutes, so a buffered hop would withhold every file already on disk and lose the lot if a
        // later step threw.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__exportDbaInstanceProcess"))
            {
                if (sentinel["__exportDbaInstanceProcess"] is Hashtable state)
                {
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
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
        }, ProcessScript,
            SqlInstance, SqlCredential, Credential, AzureCredential, EncryptionPassword, DecryptionPassword,
            Exclude, NoRecovery.ToBool(), IncludeDbMasterKey.ToBool(), NoPrefix.ToBool(),
            ExcludePassword.ToBool(), Force.ToBool(), EnableException.ToBool(), _beginState,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // The source's end block only reports timings, and it carries no Test-FunctionInterrupt, so it
    // runs even after a latched record - guarding here would drop lines the function world emits.
    protected override void EndProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, EndScript,
            _beginState, EnableException.ToBool(),
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

    // PS: the begin block VERBATIM apart from the two bind-time defaults resolved ahead of it and the
    // Get-ExportedFileInfo declaration, which moves to the process hop (a declaration carries no
    // state). The sentinel carries everything process and end read out of begin's scope.
    private const string BeginScript = """
param($Path, $BatchSeparator, $ScriptingOption, $EnableException, $__boundPath, $__boundBatchSeparator, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$Path, [string]$BatchSeparator, [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOption, $EnableException, $__boundPath, $__boundBatchSeparator, $__boundVerbose, $__boundDebug)

    # The source's bind-time defaults, which a compiled property initializer cannot express.
    if (-not $__boundPath) { $Path = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport' }
    if (-not $__boundBatchSeparator) { $BatchSeparator = Get-DbatoolsConfigValue -FullName 'formatting.batchseparator' }

    . {
        $null = Test-ExportDirectory -Path $Path

        if (-not $ScriptingOption) {
            $ScriptingOption = New-DbaScriptingOption
        }

        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        $started = Get-Date

        $eol = [System.Environment]::NewLine
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __exportDbaInstanceBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value); ScriptingOption = $ScriptingOption; Elapsed = $elapsed; Started = $started; Eol = $eol; ResolvedPath = $Path; ResolvedBatchSeparator = $BatchSeparator } }
} $Path $BatchSeparator $ScriptingOption $EnableException $__boundPath $__boundBatchSeparator $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM inside the named-wrapper shim. Edits: -FunctionName
    // Export-DbaInstance (plus -ModuleName "dbatools" on Write-Message) on every DIRECT call, none
    // inside Get-ExportedFileInfo; begin's state restores before the body; the latch is read at
    // Scope 0 after it so a Failure on this record silences later records.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Credential, $AzureCredential, $EncryptionPassword, $DecryptionPassword, $Exclude, $NoRecovery, $IncludeDbMasterKey, $NoPrefix, $ExcludePassword, $Force, $EnableException, $__beginState, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [PSCredential]$Credential, [string]$AzureCredential, [Security.SecureString]$EncryptionPassword, [Security.SecureString]$DecryptionPassword, [string[]]$Exclude, $NoRecovery, $IncludeDbMasterKey, $NoPrefix, $ExcludePassword, $Force, $EnableException, $__beginState, $__boundVerbose, $__boundDebug)

    # begin's once-computed state
    $Path = $__beginState.ResolvedPath
    $BatchSeparator = $__beginState.ResolvedBatchSeparator
    $ScriptingOption = $__beginState.ScriptingOption
    $eol = $__beginState.Eol

    function Get-ExportedFileInfo {
        param (
            [Parameter(Mandatory)]
            [object]$Server,
            [Parameter(Mandatory)]
            [string]$SourcePath,
            [Parameter(Mandatory)]
            [string]$DestinationDirectory,
            [switch]$CopyFromServer
        )

        if ([string]::IsNullOrWhiteSpace($SourcePath) -or $SourcePath -eq "Password required to export key") {
            return
        }

        $targetPath = $SourcePath
        if ($CopyFromServer) {
            $sourcePathUnc = Join-AdminUnc -Servername $Server.ComputerName -Filepath $SourcePath
            $targetPath = Join-Path -Path $DestinationDirectory -ChildPath (Split-Path -Path $SourcePath -Leaf)

            try {
                Copy-Item -Path $sourcePathUnc -Destination $targetPath -Force -ErrorAction Stop
            } catch {
                Stop-Function -Message "Failed to copy staged export artifact $SourcePath from $($Server.DomainInstanceName) to $DestinationDirectory." -ErrorRecord $_ -Target $SourcePath
                return
            }

            try {
                Remove-Item -Path $sourcePathUnc -Force -ErrorAction Stop
            } catch {
                Write-Message -Level Verbose -Message "Failed to remove staged export artifact $sourcePathUnc."
            }
        }

        Get-ChildItem -ErrorAction Ignore -Path $targetPath
    }

    # Named-wrapper shim: Write-ProgressHelper reads (Get-PSCallStack)[1].Command for both its
    # activity string and its step total, so the body has to run inside a frame carrying the
    # command's name. Dot-invoked, so the two early returns exit only the body and the latch read
    # below still runs.
    function Export-DbaInstance {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            $stepCounter = 0
            try {
                $server = $null
                $dacOpened = $false
                try {
                    # Do we need a dedicated admin connection for password retrieval?
                    # If not both are excluded, we do
                    $dacNeeded = $Exclude -notcontains 'Credentials' -or $Exclude -notcontains 'LinkedServers'
                    # If passwords are excluded, we don't need a DAC
                    if ($ExcludePassword) { $dacNeeded = $false }

                    # Do we have a dedicated admin connection already?
                    $dacConnected = $instance.Type -eq 'Server' -and $instance.InputObject.Name -match '^ADMIN:'

                    if ($dacNeeded) {
                        if ($dacConnected) {
                            Write-Message -Level Verbose -Message "Reusing dedicated admin connection for password retrieval." -FunctionName Export-DbaInstance -ModuleName "dbatools"
                            $server = $instance.InputObject
                        } else {
                            Write-Message -Level Verbose -Message "Opening dedicated admin connection for password retrieval." -FunctionName Export-DbaInstance -ModuleName "dbatools"
                            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10 -DedicatedAdminConnection -WarningAction SilentlyContinue
                            $dacOpened = $true
                        }
                    } else {
                        Write-Message -Level Verbose -Message "Opening or reusing normal connection because passwords are excluded." -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
                    }
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Export-DbaInstance
                }

                if ($Force) {
                    # when the caller requests to overwrite existing scripts we won't add the dynamic timestamp to the folder name, so that a pre-existing location can be overwritten.
                    $exportPath = Join-DbaPath -Path $Path -Child "$($server.DomainInstanceName.replace('\', '$'))"
                } else {
                    $timeNow = (Get-Date -UFormat (Get-DbatoolsConfigValue -FullName 'formatting.uformat'))
                    $exportPath = Join-DbaPath -Path $Path -Child "$($server.DomainInstanceName.replace('\', '$'))-$timeNow"
                }

                # Ensure the export dir exists.
                if (-not (Test-Path $exportPath)) {
                    try {
                        $null = New-Item -ItemType Directory -Path $exportPath -Force -ErrorAction Stop
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -FunctionName Export-DbaInstance
                        return
                    }
                }

                try {
                    $copyDbKeyExports = $false
                    if ($IncludeDbMasterKey) {
                        $copyDbKeyExports = -not (Test-DbaPath -SqlInstance $server -Path $exportPath)
                        if ($copyDbKeyExports) {
                            Write-Message -Level Verbose -Message "Export path $exportPath is not accessible from $($server.DomainInstanceName). Database certificates and keys will be staged on the SQL Server host and copied back to the export directory." -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        }
                    }

                    if ($Exclude -notcontains 'SpConfigure') {
                        Write-Message -Level Verbose -Message "Exporting SQL Server Configuration" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting SQL Server Configuration"
                        Export-DbaSpConfigure -SqlInstance $server -FilePath "$exportPath\sp_configure.sql" -EnableException:$EnableException
                        # no call to Get-ChildItem because Export-DbaSpConfigure does it
                    }

                    if ($Exclude -notcontains 'CustomErrors') {
                        Write-Message -Level Verbose -Message "Exporting custom errors (user defined messages)" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting custom errors (user defined messages)"
                        $null = Get-DbaCustomError -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\customererrors.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        Get-ChildItem -ErrorAction Ignore -Path "$exportPath\customererrors.sql"
                    }

                    if ($Exclude -notcontains 'ServerRoles') {
                        Write-Message -Level Verbose -Message "Exporting server roles" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting server roles"
                        $null = Get-DbaServerRole -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\serverroles.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        Get-ChildItem -ErrorAction Ignore -Path "$exportPath\serverroles.sql"
                    }

                    if ($Exclude -notcontains 'Credentials') {
                        Write-Message -Level Verbose -Message "Exporting SQL credentials" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting SQL credentials"
                        $null = Export-DbaCredential -SqlInstance $server -Credential $Credential -FilePath "$exportPath\credentials.sql" -ExcludePassword:$ExcludePassword -EnableException:$EnableException
                        Get-ChildItem -ErrorAction Ignore -Path "$exportPath\credentials.sql"
                    }

                    if ($Exclude -notcontains 'Logins') {
                        Write-Message -Level Verbose -Message "Exporting logins" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting logins"
                        Export-DbaLogin -SqlInstance $server -FilePath "$exportPath\logins.sql" -ExcludePassword:$ExcludePassword -NoPrefix:$NoPrefix -WarningAction SilentlyContinue -EnableException:$EnableException
                        # no call to Get-ChildItem because Export-DbaLogin does it
                    }

                    if ($Exclude -notcontains 'DatabaseMail') {
                        Write-Message -Level Verbose -Message "Exporting database mail" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting database mail"
                        # The first invocation to Export-DbaScript needs to have -Append:$false so that the previous file contents are discarded. Otherwise, the file would end up with duplicate SQL.
                        # The subsequent calls to Export-DbaScript need to have -Append:$true because this is a multi-step export and the objects are written to the same file.
                        $null = Get-DbaDbMailConfig -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\dbmail.sql" -Append:$false -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        $null = Get-DbaDbMailAccount -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\dbmail.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        $null = Get-DbaDbMailProfile -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\dbmail.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        $null = Get-DbaDbMailServer -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\dbmail.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException

                        Get-ChildItem -ErrorAction Ignore -Path "$exportPath\dbmail.sql"
                    }

                    if ($Exclude -notcontains 'CentralManagementServer') {
                        Write-Message -Level Verbose -Message "Exporting Central Management Server" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Central Management Server"
                        $outputFilePath = "$exportPath\regserver.xml"
                        $null = Export-DbaRegServer -SqlInstance $server -FilePath $outputFilePath -Overwrite:$Force -EnableException:$EnableException
                        Get-ChildItem -ErrorAction Ignore -Path $outputFilePath
                    }

                    if ($Exclude -notcontains 'BackupDevices') {
                        Write-Message -Level Verbose -Message "Exporting Backup Devices" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Backup Devices"
                        $null = Get-DbaBackupDevice -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\backupdevices.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        Get-ChildItem -ErrorAction Ignore -Path "$exportPath\backupdevices.sql"
                    }

                    if ($Exclude -notcontains 'LinkedServers') {
                        Write-Message -Level Verbose -Message "Exporting linked servers" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting linked servers"
                        Export-DbaLinkedServer -SqlInstance $server -FilePath "$exportPath\linkedservers.sql" -Credential $Credential -ExcludePassword:$ExcludePassword -EnableException:$EnableException
                        # no call to Get-ChildItem because Export-DbaLinkedServer does it
                    }

                    if ($Exclude -notcontains 'SystemTriggers') {
                        Write-Message -Level Verbose -Message "Exporting System Triggers" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting System Triggers"
                        $null = Get-DbaInstanceTrigger -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\servertriggers.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        $triggers = Get-Content -Path "$exportPath\servertriggers.sql" -Raw -ErrorAction Ignore
                        if ($triggers) {
                            $triggers = $triggers.ToString() -replace 'CREATE TRIGGER', "$BatchSeparator$($eol)CREATE TRIGGER"
                            $triggers = $triggers.ToString() -replace 'ENABLE TRIGGER', "$BatchSeparator$($eol)ENABLE TRIGGER"
                            $null = $triggers | Set-Content -Path "$exportPath\servertriggers.sql" -Force
                            Get-ChildItem -ErrorAction Ignore -Path "$exportPath\servertriggers.sql"
                        }
                    }

                    if ($Exclude -notcontains 'Databases') {
                        Write-Message -Level Verbose -Message "Exporting database restores" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting database restores"
                        Get-DbaDbBackupHistory -SqlInstance $server -Last -WarningAction SilentlyContinue -EnableException:$EnableException | Restore-DbaDatabase -SqlInstance $server -NoRecovery:$NoRecovery -WithReplace -OutputScriptOnly -WarningAction SilentlyContinue -AzureCredential $AzureCredential -EnableException:$EnableException | Out-File -FilePath "$exportPath\databases.sql"
                        Get-ChildItem -ErrorAction Ignore -Path "$exportPath\databases.sql"
                    }

                    if ($Exclude -notcontains 'Audits') {
                        Write-Message -Level Verbose -Message "Exporting Audits" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Audits"
                        $null = Get-DbaInstanceAudit -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\audits.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        Get-ChildItem -ErrorAction Ignore -Path "$exportPath\audits.sql"
                    }

                    if ($Exclude -notcontains 'ServerAuditSpecifications') {
                        Write-Message -Level Verbose -Message "Exporting Server Audit Specifications" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Server Audit Specifications"
                        $null = Get-DbaInstanceAuditSpecification -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\auditspecs.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        Get-ChildItem -ErrorAction Ignore -Path "$exportPath\auditspecs.sql"
                    }

                    if ($Exclude -notcontains 'Endpoints') {
                        Write-Message -Level Verbose -Message "Exporting Endpoints" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Endpoints"
                        $null = Get-DbaEndpoint -SqlInstance $server -EnableException:$EnableException | Where-Object IsSystemObject -EQ $false | Export-DbaScript -FilePath "$exportPath\endpoints.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        Get-ChildItem -ErrorAction Ignore -Path "$exportPath\endpoints.sql"
                    }

                    if ($Exclude -notcontains 'PolicyManagement' -and $PSVersionTable.PSEdition -eq "Core") {
                        Write-Message -Level Verbose -Message "Skipping Policy Management -- not supported by PowerShell Core" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                    }
                    if ($Exclude -notcontains 'PolicyManagement' -and $PSVersionTable.PSEdition -ne "Core") {
                        Write-Message -Level Verbose -Message "Exporting Policy Management" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Policy Management"

                        $outputFilePath = "$exportPath\policymanagement.sql"
                        $scriptText = ""
                        $policyObjects = @()

                        # the policy objects are a different set of classes and are not compatible with the SMO object usage in Export-DbaScript

                        $policyObjects += Get-DbaPbmCondition -SqlInstance $server -EnableException:$EnableException
                        $policyObjects += Get-DbaPbmObjectSet -SqlInstance $server -EnableException:$EnableException
                        $policyObjects += Get-DbaPbmPolicy -SqlInstance $server -EnableException:$EnableException

                        foreach ($policyObject in $policyObjects) {
                            $tsqlScript = $policyObject.ScriptCreate()
                            $scriptText += $tsqlScript.GetScript() + "$eol$BatchSeparator$eol$eol"
                        }

                        Set-Content -Path $outputFilePath -Value $scriptText

                        Get-ChildItem -ErrorAction Ignore -Path "$exportPath\policymanagement.sql"
                    }

                    if ($Exclude -notcontains 'ResourceGovernor') {
                        Write-Message -Level Verbose -Message "Exporting Resource Governor" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Resource Governor"
                        # The first invocation to Export-DbaScript needs to have -Append:$false so that the previous file contents are discarded. Otherwise, the file would end up with duplicate SQL.
                        # The subsequent calls to Export-DbaScript need to have -Append:$true because this is a multi-step export and the objects are written to the same file.
                        $null = Get-DbaRgClassifierFunction -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\resourcegov.sql" -Append:$false -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        $null = Get-DbaRgResourcePool -SqlInstance $server -EnableException:$EnableException | Where-Object Name -NotIn 'default', 'internal' | Export-DbaScript -FilePath "$exportPath\resourcegov.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        $null = Get-DbaRgWorkloadGroup -SqlInstance $server -EnableException:$EnableException | Where-Object Name -NotIn 'default', 'internal' | Export-DbaScript -FilePath "$exportPath\resourcegov.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        $null = Get-DbaResourceGovernor -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\resourcegov.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        Get-ChildItem -ErrorAction Ignore -Path "$exportPath\resourcegov.sql"
                    }

                    if ($Exclude -notcontains 'ExtendedEvents') {
                        Write-Message -Level Verbose -Message "Exporting Extended Events" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Extended Events"
                        $null = Get-DbaXESession -SqlInstance $server -EnableException:$EnableException | Export-DbaXESession -FilePath "$exportPath\extendedevents.sql" -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix -EnableException:$EnableException
                        Get-ChildItem -ErrorAction Ignore -Path "$exportPath\extendedevents.sql"
                    }

                    if ($Exclude -notcontains 'AgentServer') {
                        Write-Message -Level Verbose -Message "Exporting job server" -FunctionName Export-DbaInstance -ModuleName "dbatools"

                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting job server"
                        # The first invocation to Export-DbaScript needs to have -Append:$false so that the previous file contents are discarded. Otherwise, the file would end up with duplicate SQL.
                        # The subsequent calls to Export-DbaScript need to have -Append:$true because this is a multi-step export and the objects are written to the same file.
                        $null = Get-DbaAgentJobCategory -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$false -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        $null = Get-DbaAgentOperator -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        $null = Get-DbaAgentAlert -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        $null = Get-DbaAgentProxy -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        $null = Get-DbaAgentSchedule -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        $null = Get-DbaAgentJob -SqlInstance $server -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix -EnableException:$EnableException
                        Get-ChildItem -ErrorAction Ignore -Path "$exportPath\sqlagent.sql"
                    }

                    if ($Exclude -notcontains 'ReplicationSettings') {
                        Write-Message -Level Verbose -Message "Exporting replication settings" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting replication settings"

                        try {
                            $null = Export-DbaReplServerSetting -SqlInstance $instance -SqlCredential $SqlCredential -FilePath "$exportPath\replication.sql" -EnableException
                            Get-ChildItem -ErrorAction Ignore -Path "$exportPath\replication.sql"
                        } catch {
                            Write-Message -Level Verbose -Message "Replication failed, skipping" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        }
                    }

                    if ($Exclude -notcontains 'SysDbUserObjects') {
                        Write-Message -Level Verbose -Message "Exporting user objects in system databases (this can take a minute)." -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting user objects in system databases (this can take a minute)."
                        $outputFile = "$exportPath\userobjectsinsysdbs.sql"
                        $sysDbUserObjects = Export-DbaSysDbUserObject -SqlInstance $server -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix -ScriptingOptionsObject $ScriptingOption -PassThru -EnableException:$EnableException
                        Set-Content -Path $outputFile -Value $sysDbUserObjects # this approach is needed because -Append is used in Export-DbaSysDbUserObject.ps1
                        Get-ChildItem -ErrorAction Ignore -Path $outputFile
                    }

                    if ($Exclude -notcontains 'AvailabilityGroups') {
                        Write-Message -Level Verbose -Message "Exporting availability group" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting availability groups"
                        $null = Get-DbaAvailabilityGroup -SqlInstance $server -WarningAction SilentlyContinue -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\AvailabilityGroups.sql" -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix -ScriptingOptionsObject $ScriptingOption -EnableException:$EnableException
                        Get-ChildItem -ErrorAction Ignore -Path "$exportPath\AvailabilityGroups.sql"
                    }

                    if ($Exclude -notcontains 'OleDbProvider') {
                        Write-Message -Level Verbose -Message "Exporting OLEDB Providers" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting OLEDB Providers"
                        $null = Get-DbaOleDbProvider -SqlInstance $server -WarningAction SilentlyContinue -EnableException:$EnableException | Export-DbaScript -FilePath "$exportPath\OleDbProvider.sql" -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix -ScriptingOptionsObject $ScriptingOption -EnableException:$EnableException
                        Get-ChildItem -ErrorAction Ignore -Path "$exportPath\oledbprovider.sql"
                    }

                    if ($IncludeDbMasterKey -and $Exclude -notcontains 'DbCertificates') {
                        Write-Message -Level Verbose -Message "Exporting database certificates" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting database certificates"
                        $splatDbCert = @{
                            SqlInstance     = $server
                            EnableException = $EnableException
                        }
                        if (-not $copyDbKeyExports) {
                            $splatDbCert["Path"] = $exportPath
                        }
                        if ($EncryptionPassword) {
                            $splatDbCert["EncryptionPassword"] = $EncryptionPassword
                        }
                        if ($DecryptionPassword) {
                            $splatDbCert["DecryptionPassword"] = $DecryptionPassword
                        }
                        $databaseCertificates = Backup-DbaDbCertificate @splatDbCert
                        foreach ($databaseCertificate in $databaseCertificates) {
                            Get-ExportedFileInfo -Server $server -SourcePath $databaseCertificate.Path -DestinationDirectory $exportPath -CopyFromServer:$copyDbKeyExports
                            Get-ExportedFileInfo -Server $server -SourcePath $databaseCertificate.Key -DestinationDirectory $exportPath -CopyFromServer:$copyDbKeyExports
                        }
                    }

                    if ($IncludeDbMasterKey -and $EncryptionPassword) {
                        Write-Message -Level Verbose -Message "Exporting database master keys" -FunctionName Export-DbaInstance -ModuleName "dbatools"
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting database master keys"
                        $splatMasterKey = @{
                            SqlInstance     = $server
                            SecurePassword  = $EncryptionPassword
                            EnableException = $EnableException
                        }
                        if (-not $copyDbKeyExports) {
                            $splatMasterKey["Path"] = $exportPath
                        }
                        $databaseMasterKeys = Backup-DbaDbMasterKey @splatMasterKey
                        foreach ($databaseMasterKey in $databaseMasterKeys) {
                            Get-ExportedFileInfo -Server $server -SourcePath $databaseMasterKey.Filename -DestinationDirectory $exportPath -CopyFromServer:$copyDbKeyExports
                        }
                    } elseif ($IncludeDbMasterKey -and -not $EncryptionPassword) {
                        Write-Message -Level Warning -Message "IncludeDbMasterKey was specified but no EncryptionPassword was provided. Skipping database master key export." -FunctionName Export-DbaInstance -ModuleName "dbatools"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Export-DbaInstance
                }
            } finally {
                Write-Progress -Activity "Performing Instance Export for $instance" -Completed
                if ($dacOpened -and $null -ne $server) {
                    $null = $server | Disconnect-DbaInstance -WhatIf:$false
                }
            }
        }
    }
    . Export-DbaInstance

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __exportDbaInstanceProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $SqlInstance $SqlCredential $Credential $AzureCredential $EncryptionPassword $DecryptionPassword $Exclude $NoRecovery $IncludeDbMasterKey $NoPrefix $ExcludePassword $Force $EnableException $__beginState $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM, with begin's stopwatch and start timestamp restored from the
    // sentinel and -FunctionName/-ModuleName attribution on the four Write-Message calls.
    private const string EndScript = """
param($__beginState, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__beginState, $EnableException, $__boundVerbose, $__boundDebug)

    # begin's once-computed state
    $elapsed = $__beginState.Elapsed
    $started = $__beginState.Started

    $totalTime = ($elapsed.Elapsed.toString().Split(".")[0])
    Write-Message -Level Verbose -Message "SQL Server export complete." -FunctionName Export-DbaInstance -ModuleName "dbatools"
    Write-Message -Level Verbose -Message "Export started: $started" -FunctionName Export-DbaInstance -ModuleName "dbatools"
    Write-Message -Level Verbose -Message "Export completed: $(Get-Date)" -FunctionName Export-DbaInstance -ModuleName "dbatools"
    Write-Message -Level Verbose -Message "Total Elapsed time: $totalTime" -FunctionName Export-DbaInstance -ModuleName "dbatools"
} $__beginState $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

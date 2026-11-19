#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Installs or updates Adam Machanic's sp_WhoIsActive on a target database. The local-cache refresh,
/// version-specific SQL selection, optional GUI database prompt, and ShouldProcess flow remain a
/// module-scoped PowerShell compatibility hop; this cmdlet supplies the real ShouldProcess runtime and
/// preserves the advanced function's begin/process lifetime. Surface pinned by
/// migration/baselines/Install-DbaWhoIsActive.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Install, "DbaWhoIsActive", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class InstallDbaWhoIsActiveCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Install from a local file instead of downloading.</summary>
    [Parameter]
    [ValidateLocalFile]
    [PsStringCast]
    public string? LocalFile { get; set; }

    /// <summary>The database to install sp_WhoIsActive into.</summary>
    [Parameter]
    public object? Database { get; set; }

    /// <summary>Force a refresh of the local cached copy of the software.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _localCachedCopy;
    private bool _beginInterrupted;
    // The GUI-cancel path (source :190 Stop-Function with NO -Continue) sets a function-scoped interrupt that
    // stops ALL later pipeline records in the function (process' Test-FunctionInterrupt guard at the top). A
    // per-record hop loses it, so we carry the interrupt out of process and latch it to guard later records.
    private bool _processInterrupted;
    // $Database is a function-scoped param that the GUI prompt (Show-DbaDbList) REASSIGNS when -Database is
    // omitted, and it is then read at the top of the NEXT pipeline record - so the selection leaks forward
    // (record 2 reuses record 1's pick instead of re-prompting). A per-record hop resets it, so we carry it
    // (reproduce-not-sanitize) - the InstallDbaAgentAdminAlert $Operator class. Starts as the bound value.
    private object? _databaseState;
    private bool _databaseInitialized;
    // $null = Invoke-DbaQuery suppresses query rows, but the process still emits a status object and carries
    // $Database out; a per-invocation GUID token keeps the carrier sentinel from colliding with output.
    private readonly string _processToken = Guid.NewGuid().ToString("N");

    /// <summary>PS: [ValidateScript( { Test-Path -Path $_ -PathType Leaf } )]. Reproduced by running the
    /// REAL Test-Path via the engine at bind time (File.Exists diverges from Test-Path's PSDrive-relative,
    /// provider-qualified and wildcard path semantics), throwing the exact PS validation-script failure text.</summary>
    private sealed class ValidateLocalFileAttribute : ValidateArgumentsAttribute
    {
        protected override void Validate(object arguments, EngineIntrinsics engineIntrinsics)
        {
            string? text = arguments as string ?? (arguments is null ? null : (string)LanguagePrimitives.ConvertTo(arguments, typeof(string), System.Globalization.CultureInfo.InvariantCulture));
            ScriptBlock testPath = ScriptBlock.Create("param($p) Test-Path -Path $p -PathType Leaf");
            System.Collections.ObjectModel.Collection<PSObject> result = engineIntrinsics.InvokeCommand.InvokeScript(false, testPath, null, text);
            bool valid = result.Count > 0 && LanguagePrimitives.IsTrue(result[0]);
            if (!valid)
            {
                string script = " Test-Path -Path $_ -PathType Leaf ";
                throw new ValidationMetadataException("The \"" + script + "\" validation script for the argument with value \"" + text + "\" did not return a result of True. Determine why the validation script failed, and then try the command again.");
            }
        }
    }

    protected override void BeginProcessing()
    {
        bool completed = false;
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Force.ToBool(), LocalFile, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__InstallWhoIsActiveBeginComplete"]?.Value))
            {
                _localCachedCopy = UnwrapHopValue(item.Properties["LocalCachedCopy"]?.Value);
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
        if (_beginInterrupted || _processInterrupted || Interrupted)
            return;

        if (!_databaseInitialized)
        {
            _databaseState = Database;
            _databaseInitialized = true;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && string.Equals(
                item.Properties["__InstallWhoIsActiveProcessComplete"]?.Value as string, _processToken, StringComparison.Ordinal))
            {
                _databaseState = UnwrapHopValue(item.Properties["Database"]?.Value);
                _processInterrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, _databaseState, _localCachedCopy, Force.ToBool(),
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
param($Force, $LocalFile, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param($Force, [string]$LocalFile, $EnableException, $__realCmdlet)

    if ($Force) { $ConfirmPreference = 'none' }

    # Do we need a new local cached version of the software?
    $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
    $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child 'WhoIsActive'
    if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
        if ($__realCmdlet.ShouldProcess('WhoIsActive', 'Update local cached copy of the software')) {
            try {
                Save-DbaCommunitySoftware -Software WhoIsActive -LocalFile $LocalFile -EnableException
            } catch {
                Stop-Function -Message 'Failed to update local cached copy' -ErrorRecord $_ -FunctionName Install-DbaWhoIsActive
            }
        }
    }

    [pscustomobject]@{ __InstallWhoIsActiveBeginComplete = $true; LocalCachedCopy = $localCachedCopy; Interrupted = [bool](Test-FunctionInterrupt) }
} $Force $LocalFile $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $localCachedCopy, $Force, $EnableException, $__realCmdlet, $__processToken, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, $Database, $localCachedCopy, $Force, $EnableException, $__realCmdlet, $__processToken)

    # -Force sets function-scoped $ConfirmPreference='none' in the SOURCE begin, persisting across process
    # records; separate hops don't share that scope, so re-establish it here (T26, carried via $Force).
    if ($Force) { $ConfirmPreference = 'none' }
    . {
    if (Test-FunctionInterrupt) { return }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Install-DbaWhoIsActive
        }

        # Select the appropriate SQL file based on the target server's version.
        # sp_WhoIsActive ships version-specific SQL files in subfolders:
        # - Folder "2008" for SQL Server 2005-2008 (VersionMajor <= 10)
        # - Folder "2019" for SQL Server 2012-2019 (VersionMajor <= 15)
        # - Base folder for SQL Server 2022+ (VersionMajor >= 16)
        if ($server.VersionMajor -le 10) {
            $sqlfile = Join-Path -Path (Join-Path -Path $localCachedCopy -ChildPath '2008') -ChildPath 'sp_WhoIsActive.sql'
        } elseif ($server.VersionMajor -le 15) {
            $sqlfile = Join-Path -Path (Join-Path -Path $localCachedCopy -ChildPath '2019') -ChildPath 'sp_WhoIsActive.sql'
        } else {
            $sqlfile = Join-Path -Path $localCachedCopy -ChildPath 'sp_WhoIsActive.sql'
        }

        if (-not (Test-Path -Path $sqlfile)) {
            Write-Message -Level Verbose -Message "Version-appropriate file not found at $sqlfile, falling back to old filename who_is_active.sql." -FunctionName Install-DbaWhoIsActive -ModuleName "dbatools"
            $whoIsActiveOldFile = Get-ChildItem -Path $localCachedCopy -Filter 'who_is_active.sql' -Recurse | Select-Object -First 1
            if ($whoIsActiveOldFile) {
                $sqlfile = $whoIsActiveOldFile.FullName
            } else {
                Stop-Function -Message "No SQL file found in $localCachedCopy." -Target $instance -Continue -FunctionName Install-DbaWhoIsActive
                continue
            }
        }

        Write-Message -Level Verbose -Message "Using $sqlfile." -FunctionName Install-DbaWhoIsActive -ModuleName "dbatools"
        $sql = [IO.File]::ReadAllText($sqlfile)
        $sql = $sql -replace 'USE master', ''

        $matchString = 'Who Is Active? v'
        if ($sql -like "*$matchString*") {
            $posStart = $sql.IndexOf($matchString)
            $posEnd = $sql.IndexOf(")", $posStart)
            $versionWhoIsActive = $sql.Substring($posStart + $matchString.Length, $posEnd - ($posStart + $matchString.Length) + 1).TrimEnd()
        } else {
            $versionWhoIsActive = ''
        }

        if (-not $Database) {
            if ($__realCmdlet.ShouldProcess($instance, "Prompting with GUI list of databases")) {
                $Database = Show-DbaDbList -SqlInstance $server -Title "Install sp_WhoisActive" -Header "To deploy sp_WhoisActive, select a database or hit cancel to quit." -DefaultDb "master"

                if (-not $Database) {
                    Stop-Function -Message "You must select a database to install the procedure." -Target $Database -FunctionName Install-DbaWhoIsActive
                    return
                }

                if ($Database -ne 'master') {
                    Write-Message -Level Warning -Message "You have selected a database other than master. When you run Invoke-DbaWhoIsActive in the future, you must specify -Database $Database." -FunctionName Install-DbaWhoIsActive -ModuleName "dbatools"
                }
            }
        }
        if ($__realCmdlet.ShouldProcess($instance, "Installing sp_WhoisActive")) {
            try {
                $ProcedureExists_Query = "SELECT COUNT(*) [proc_count] FROM sys.procedures WHERE is_ms_shipped = 0 AND name LIKE '%sp_WhoisActive%'"

                if ($server.Databases[$Database]) {
                    $ProcedureExists = ($server.Query($ProcedureExists_Query, $Database)).proc_count
                    try {
                        # We use Invoke-DbaQuery because using ExecuteNonQuery with long batches causes problems on AppVeyor.
                        $null = Invoke-DbaQuery -SqlInstance $server -Database $Database -Query $sql -EnableException
                    } catch {
                        Stop-Function -Message "Failed to install stored procedure." -ErrorRecord $_ -Continue -Target $instance -FunctionName Install-DbaWhoIsActive
                    }

                    if ($ProcedureExists -gt 0) {
                        $status = 'Updated'
                    } else {
                        $status = 'Installed'
                    }


                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $Database
                        Name         = 'sp_WhoisActive'
                        Version      = $versionWhoIsActive
                        Status       = $status
                    }
                } else {
                    Stop-Function -Message "Failed to find database $Database on $instance or $Database is not writeable." -Continue -Target $instance -FunctionName Install-DbaWhoIsActive
                }

            } catch {
                Stop-Function -Message "Failed to install stored procedure." -ErrorRecord $_ -Continue -Target $instance -FunctionName Install-DbaWhoIsActive
            }

        }
    }
    }
    [pscustomobject]@{ __InstallWhoIsActiveProcessComplete = $__processToken; Database = $Database; Interrupted = [bool](Test-FunctionInterrupt) }
} $SqlInstance $SqlCredential $Database $localCachedCopy $Force $EnableException $__realCmdlet $__processToken @__commonParameters 3>&1 2>&1
""";
}

#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Runs Microsoft's Azure SQL Tips script against Azure SQL Database instances. The local-cache
/// refresh (Save-DbaCommunitySoftware), tips-query selection/rewrite, per-instance connect and the
/// per-database Invoke-DbaQuery emission remain a module-scoped PowerShell compatibility hop; this
/// cmdlet supplies the begin/process lifetime and carries the function-scoped state the source leaks
/// across pipeline records. Surface pinned by migration/baselines/Invoke-DbaDbAzSqlTip.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbAzSqlTip")]
public sealed class InvokeDbaDbAzSqlTipCommand : DbaBaseCmdlet
{
    // The source advanced function declares no explicit Position on any parameter, so PowerShell's
    // default positional binding auto-assigns positions to the non-switch parameters in declaration
    // order (0-7); switches stay named-only. The compiled cmdlet pins those same positions to keep
    // the surface byte-identical to migration/baselines/Invoke-DbaDbAzSqlTip.json.

    /// <summary>The target Azure SQL instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The Azure SQL domain for connection (sovereign clouds override the default).</summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    public string AzureDomain { get; set; } = "database.windows.net";

    /// <summary>The Azure AD tenant ID (GUID) used for authentication.</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    public string? Tenant { get; set; }

    /// <summary>Run a local copy of the Azure SQL Tips script instead of downloading it.</summary>
    [Parameter(Position = 4)]
    [ValidateLocalFile]
    [PsStringCast]
    public string? LocalFile { get; set; }

    /// <summary>The Azure SQL databases to analyze.</summary>
    [Parameter(Position = 5)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>The Azure SQL databases to skip.</summary>
    [Parameter(Position = 6)]
    [PsStringArrayCast]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Analyze every user database on the instance.</summary>
    [Parameter]
    public SwitchParameter AllUserDatabases { get; set; }

    /// <summary>Return all tips regardless of the database's current state.</summary>
    [Parameter]
    public SwitchParameter ReturnAllTips { get; set; }

    /// <summary>Use the compatibility-level-100 variant of the tips script.</summary>
    [Parameter]
    public SwitchParameter Compat100 { get; set; }

    /// <summary>The query timeout, in minutes, for the tips analysis.</summary>
    [Parameter(Position = 7)]
    public int StatementTimeout { get; set; }

    /// <summary>Force a fresh download of the tips script from GitHub.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _azTipsQuery;
    // $Database is a function-scoped param the source REASSIGNS from -AllUserDatabases inside the
    // process block; in the source's single process scope that assignment (and its non-assignment on
    // an instance-level connect failure) persists into the NEXT piped record. A per-record hop resets
    // it, so we carry it forward to reproduce the source's cross-record behaviour. Starts at the bound value.
    private object? _databaseState;
    private bool _databaseInitialized;
    // $failedInstConn is set true on an instance-level connect failure and NEVER reset by the source, so
    // once one piped instance fails at instance level every later record takes the per-database reconnect
    // path. That leak is reproduced (bug-for-bug) by carrying the flag across records.
    private bool _failedInstConn;
    // Per-invocation token so the process carrier sentinel is distinguishable from real tip output.
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
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Database, ExcludeDatabase, AllUserDatabases.ToBool(), Force.ToBool(), LocalFile,
            Compat100.ToBool(), ReturnAllTips.ToBool(), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__AzSqlTipBeginComplete"]?.Value))
            {
                _azTipsQuery = UnwrapHopValue(item.Properties["AzTipsQuery"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }
    }

    protected override void ProcessRecord()
    {
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
                item.Properties["__AzSqlTipProcessComplete"]?.Value as string, _processToken, StringComparison.Ordinal))
            {
                _databaseState = UnwrapHopValue(item.Properties["Database"]?.Value);
                _failedInstConn = LanguagePrimitives.IsTrue(item.Properties["FailedInstConn"]?.Value);
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, AzureDomain, Tenant, StatementTimeout, _databaseState,
            AllUserDatabases.ToBool(), _azTipsQuery, EnableException.ToBool(), _failedInstConn, _processToken,
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
param($Database, $ExcludeDatabase, $AllUserDatabases, $Force, $LocalFile, $Compat100, $ReturnAllTips, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($Database, $ExcludeDatabase, $AllUserDatabases, $Force, [string]$LocalFile, $Compat100, $ReturnAllTips, $EnableException)

    if ($Force) { $ConfirmPreference = 'none' }

    if (-not $Database -and -not $ExcludeDatabase -and -not $AllUserDatabases) {
        Stop-Function -Message "You must specify databases to execute against using either -Database, -ExcludeDatabase or -AllUserDatabases" -FunctionName Invoke-DbaDbAzSqlTip
        return
    }

    # Do we need a new local cached version of the software?
    $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
    $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child 'AzSqlTips'
    if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
        # The source guarded this with $PSCmdlet.ShouldProcess, but the advanced function's
        # [CmdletBinding()] never declared SupportsShouldProcess, so ShouldProcess always returned
        # $true and no -WhatIf/-Confirm surfaced. Reproduced as an unconditional branch; the compiled
        # cmdlet likewise omits ShouldProcess.
        if ($true) {
            try {
                Save-DbaCommunitySoftware -Software AzSqlTips -LocalFile $LocalFile -EnableException
            } catch {
                Stop-Function -Message 'Failed to update local cached copy' -ErrorRecord $_ -FunctionName Invoke-DbaDbAzSqlTip
            }
        }
    }

    # get the tips query code
    if ($Compat100) {
        $azTipsQuery = Get-Content (Join-DbaPath $localCachedCopy sqldb-tips 'get-sqldb-tips-compat-level-100-only.sql') -Raw
    } else {
        $azTipsQuery = Get-Content (Join-DbaPath $localCachedCopy sqldb-tips 'get-sqldb-tips.sql') -Raw
    }

    if ($ReturnAllTips) {
        # if ReturnAllTips is true set the variable to 1
        $azTipsQuery = ($azTipsQuery -replace '(?<=ReturnAllTips)(\D+)(\d+)', ('$1 1') )
    }

    [pscustomobject]@{ __AzSqlTipBeginComplete = $true; AzTipsQuery = $azTipsQuery }
} $Database $ExcludeDatabase $AllUserDatabases $Force $LocalFile $Compat100 $ReturnAllTips $EnableException @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AzureDomain, $Tenant, $StatementTimeout, $Database, $AllUserDatabases, $azTipsQuery, $EnableException, $failedInstConn, $__processToken, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string]$AzureDomain, [string]$Tenant, [int]$StatementTimeout, $Database, $AllUserDatabases, $azTipsQuery, $EnableException, $failedInstConn, $__processToken)

    foreach ($instance in $SqlInstance) {
        try {
            Write-Message -Message ('Connecting to {0}' -f $instance) -FunctionName Invoke-DbaDbAzSqlTip -ModuleName "dbatools"

            $connSplat = @{
                SqlInstance      = $instance
                SqlCredential    = $SqlCredential
                StatementTimeout = ($StatementTimeout * 60)
                AzureDomain      = $AzureDomain
                Tenant           = $Tenant
            }
            $connection = Connect-DbaInstance @connSplat

            if ($connection.DatabaseEngineType -ne 'SqlAzureDatabase') {
                Stop-Function -Message ('{0} is not an Azure SQL Database - this function only works against Azure  SQL Databases' -f $instance) -Continue -FunctionName Invoke-DbaDbAzSqlTip
            }

            if ($AllUserDatabases) {
                $Database = ($connection.Databases | Where-Object name -ne 'Master').Name
            }

        } catch {
            $failedInstConn = $true

            if ($AllUserDatabases) {
                Write-Warning -Message ("Could not connect at instance level to {0}, so we can't get the list of databases. You'll need to specify a list of databases with -Database." -f $_)
                break
            }

            Write-Warning -Message ('Could not connect at instance level, so will try to connect to database. {0}' -f $_)

        }

        foreach ($db in $Database) {

            try {

                Write-Message -Message ('Running Azure SQL Tips against {0}' -f $db) -FunctionName Invoke-DbaDbAzSqlTip -ModuleName "dbatools"

                if ($failedInstConn) {
                    Write-Message -Message ('Connecting to {0}.{1}' -f $instance, $db) -FunctionName Invoke-DbaDbAzSqlTip -ModuleName "dbatools"
                    $connection = Connect-DbaInstance @connSplat -Database $db
                }

                Invoke-DbaQuery -SqlInstance $connection -Database $db -Query $azTipsQuery -EnableException:$EnableException | ForEach-Object {
                    [PSCustomObject]@{
                        ComputerName        = $connection.ComputerName
                        InstanceName        = $connection.Name
                        SqlInstance         = $connection.DomainInstanceName
                        Database            = $db
                        tip_id              = $PSItem.tip_id
                        description         = $PSItem.description
                        confidence_percent  = $PSItem.confidence_percent
                        additional_info_url = $PSItem.additional_info_url
                        details             = $PSItem.details
                    }
                }
            } catch {
                Stop-Function -Message "Failed to run AzSqlTips against Instance." -ErrorRecord $_ -Continue -Target $instance -FunctionName Invoke-DbaDbAzSqlTip
            }
        }
    }

    [pscustomobject]@{ __AzSqlTipProcessComplete = $__processToken; Database = $Database; FailedInstConn = [bool]$failedInstConn }
} $SqlInstance $SqlCredential $AzureDomain $Tenant $StatementTimeout $Database $AllUserDatabases $azTipsQuery $EnableException $failedInstConn $__processToken @__commonParameters 3>&1 2>&1
""";
}

#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Installs or updates Brent Ozar's First Responder Kit stored procedures on target databases. The
/// local-cache refresh, script selection (begin), per-instance connection, and per-script
/// execution/ShouldProcess flow remain a module-scoped PowerShell compatibility hop; this cmdlet supplies
/// the real ShouldProcess runtime and preserves the advanced function's begin/process lifetime. Surface
/// pinned by migration/baselines/Install-DbaFirstResponderKit.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Install, "DbaFirstResponderKit", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class InstallDbaFirstResponderKitCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The source branch of the First Responder Kit repository.</summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    [ValidateSet("main", "dev")]
    public string Branch { get; set; } = "main";

    /// <summary>The database to install the First Responder Kit into.</summary>
    [Parameter(Position = 3)]
    public object Database { get; set; } = "master";

    /// <summary>Install from a local zip/folder instead of downloading.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string? LocalFile { get; set; }

    /// <summary>Install only the named script(s).</summary>
    [Parameter(Position = 5)]
    [PsStringArrayCast]
    [ValidateSet("Install-All-Scripts.sql", "Install-Azure.sql",
        "sp_Blitz.sql", "sp_BlitzFirst.sql", "sp_BlitzIndex.sql", "sp_BlitzCache.sql", "sp_BlitzWho.sql",
        "sp_BlitzAnalysis.sql", "sp_BlitzBackups.sql", "sp_BlitzLock.sql",
        "sp_DatabaseRestore.sql", "sp_ineachdb.sql",
        "SqlServerVersions.sql", "Uninstall.sql")]
    public string[]? OnlyScript { get; set; }

    /// <summary>Force a refresh of the local cached copy of the software.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _sqlScripts;
    private bool _beginInterrupted;
    // The process body runs a BARE Invoke-DbaQuery (source :229, no $null= assignment), so arbitrary
    // query-result rows flow to the pipeline. A sentinel keyed on property-name+truthiness would collide
    // with a custom -LocalFile script that emits a __InstallFrkProcessComplete column. Key the sentinel on
    // this per-invocation GUID token compared ORDINAL so real output falls through (carrier-note guidance).
    private readonly string _processToken = Guid.NewGuid().ToString("N");
    // $server is ShouldProcess-gated-assign (connect) but unconditional-read ($server.Query); a
    // connect-gate-false later record reads the prior record's Server in function scope. A per-record hop
    // resets it, so we carry it (reproduce-not-sanitize). Starts null. See PARITY-TRAPS (W4-074 class).
    private object? _carriedServer;

    protected override void BeginProcessing()
    {
        // Begin STREAMS (not buffered InvokeScoped): the source begin can emit a Stop-Function warning
        // (Save failure) and THEN hit a terminating Get-ChildItem (bad -LocalFile + -ErrorAction Stop) while
        // building $sqlScripts - buffering would lose the warning before the terminating throw (DEF-001/T1
        // emit-then-terminate, in begin). Streaming forwards the warning before the throw propagates.
        bool completed = false;
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__InstallFrkBeginComplete"]?.Value))
            {
                _sqlScripts = UnwrapHopValue(item.Properties["SqlScripts"]?.Value);
                _beginInterrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
                completed = true;
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, BeginScript,
            Force.ToBool(), LocalFile, Branch, OnlyScript, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
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
                item.Properties["__InstallFrkProcessComplete"]?.Value as string, _processToken, StringComparison.Ordinal))
            {
                _carriedServer = UnwrapHopValue(item.Properties["Server"]?.Value);
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, _sqlScripts, Force.ToBool(),
            EnableException.ToBool(), this, _carriedServer, _processToken,
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
param($Force, $LocalFile, $Branch, $OnlyScript, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param($Force, [string]$LocalFile, [string]$Branch, [string[]]$OnlyScript, $EnableException, $__realCmdlet)

    if ($Force) { $ConfirmPreference = 'none' }

    # Do we need a new local cached version of the software?
    $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
    $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child "SQL-Server-First-Responder-Kit-$Branch"
    if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
        if ($__realCmdlet.ShouldProcess('FirstResponderKit', 'Update local cached copy of the software')) {
            try {
                Save-DbaCommunitySoftware -Software FirstResponderKit -Branch $Branch -LocalFile $LocalFile -EnableException
            } catch {
                Stop-Function -Message 'Failed to update local cached copy' -ErrorRecord $_ -FunctionName Install-DbaFirstResponderKit
            }
        }
    }

    if ($OnlyScript) {
        $sqlScripts = @()
        foreach ($script in $OnlyScript) {
            $sqlScript = Get-ChildItem $LocalCachedCopy -Filter $script
            if ($sqlScript) {
                $sqlScripts += $sqlScript
            } else {
                Write-Message -Level Warning -Message "Script $script not found in $LocalCachedCopy, skipping." -FunctionName Install-DbaFirstResponderKit -ModuleName "dbatools"
            }
        }
    } else {
        $sqlScripts = Get-ChildItem $LocalCachedCopy -Filter "sp_*.sql"
        $sqlScripts += Get-ChildItem $LocalCachedCopy -Filter "SqlServerVersions.sql"
    }

    [pscustomobject]@{ __InstallFrkBeginComplete = $true; SqlScripts = $sqlScripts; Interrupted = [bool](Test-FunctionInterrupt) }
} $Force $LocalFile $Branch $OnlyScript $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $sqlScripts, $Force, $EnableException, $__realCmdlet, $__carriedServer, $__processToken, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, $Database, $sqlScripts, $Force, $EnableException, $__realCmdlet, $__carriedServer, $__processToken)

    # -Force sets function-scoped $ConfirmPreference='none' in the SOURCE begin, persisting across process
    # records; separate hops don't share that scope, so re-establish it here (T26, carried via $Force).
    if ($Force) { $ConfirmPreference = 'none' }
    # DEF-012 cross-record carrier: seed $server with the prior record's value BEFORE the loop.
    $server = $__carriedServer
    . {
    if (Test-FunctionInterrupt) { return }

    foreach ($instance in $SqlInstance) {
        if ($__realCmdlet.ShouldProcess($instance, "Connecting to $instance")) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -NonPooledConnection
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Install-DbaFirstResponderKit
            }
        }
        if ($__realCmdlet.ShouldProcess($database, "Installing FRK procedures in $database on $instance")) {
            Write-Message -Level Verbose -Message "Starting installing/updating the First Responder Kit stored procedures in $database on $instance." -FunctionName Install-DbaFirstResponderKit -ModuleName "dbatools"
            $allprocedures_query = "SELECT name FROM sys.procedures WHERE is_ms_shipped = 0"
            $allprocedures = ($server.Query($allprocedures_query, $Database)).Name

            # Install/Update each FRK stored procedure
            foreach ($script in $sqlScripts) {
                $scriptName = $script.Name
                $scriptError = $false

                $baseres = [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Database     = $Database
                    Name         = $script.BaseName
                    Status       = $null
                }

                if ($scriptName -eq "sp_BlitzQueryStore.sql" -and ($server.VersionMajor -lt 13)) {
                    Write-Message -Level Warning -Message "$instance found to be below SQL Server 2016, skipping $scriptName" -FunctionName Install-DbaFirstResponderKit -ModuleName "dbatools"
                    $baseres.Status = 'Skipped'
                    $baseres
                    continue
                }
                if ($scriptName -eq "sp_BlitzInMemoryOLTP.sql" -and ($server.VersionMajor -lt 12)) {
                    Write-Message -Level Warning -Message "$instance found to be below SQL Server 2014, skipping $scriptName" -FunctionName Install-DbaFirstResponderKit -ModuleName "dbatools"
                    $baseres.Status = 'Skipped'
                    $baseres
                    continue
                }
                if ($__realCmdlet.ShouldProcess($instance, "installing/updating $scriptName in $database")) {
                    try {
                        Invoke-DbaQuery -SqlInstance $server -Database $Database -File $script.FullName -EnableException -Verbose:$false
                    } catch {
                        Write-Message -Level Warning -Message "Could not execute at least one portion of $scriptName in $Database on $instance." -ErrorRecord $_ -FunctionName Install-DbaFirstResponderKit -ModuleName "dbatools"
                        $scriptError = $true
                    }

                    if ($scriptError) {
                        $baseres.Status = 'Error'
                    } elseif ($script.BaseName -in $allprocedures) {
                        $baseres.Status = 'Updated'
                    } else {
                        $baseres.Status = 'Installed'
                    }
                    $baseres
                }
            }
        }
        Write-Message -Level Verbose -Message "Finished installing/updating the First Responder Kit stored procedures in $database on $instance." -FunctionName Install-DbaFirstResponderKit -ModuleName "dbatools"
    }
    }
    [pscustomobject]@{ __InstallFrkProcessComplete = $__processToken; Server = $server }
} $SqlInstance $SqlCredential $Database $sqlScripts $Force $EnableException $__realCmdlet $__carriedServer $__processToken @__commonParameters 3>&1 2>&1
""";
}

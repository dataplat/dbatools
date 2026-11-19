#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Installs or updates the DarlingData stored procedures on target databases. The local-cache
/// refresh (Save-DbaCommunitySoftware), per-instance connection, script selection, and per-script
/// execution/ShouldProcess flow remain a module-scoped PowerShell compatibility hop; this cmdlet
/// supplies the real ShouldProcess runtime and preserves the advanced function's begin/process
/// lifetime. Surface pinned by migration/baselines/Install-DbaDarlingData.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Install, "DbaDarlingData", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class InstallDbaDarlingDataCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database to install the DarlingData procedures into.</summary>
    [Parameter(Position = 2)]
    public object Database { get; set; } = "master";

    /// <summary>The source branch of the DarlingData repository.</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    [ValidateSet("main", "dev")]
    public string Branch { get; set; } = "main";

    /// <summary>Which DarlingData procedures to install.</summary>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    [ValidateSet("All", "Human", "HumanEvents", "Pressure", "PressureDetector", "Quickie", "QuickieStore", "Block", "HumanEventsBlockViewer", "Log", "LogHunter", "Health", "HealthParser", "Index", "IndexCleanup", "Perf", "PerfCheck")]
    public string[] Procedure { get; set; } = new[] { "All" };

    /// <summary>Install from a local zip/folder instead of downloading.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    public string? LocalFile { get; set; }

    /// <summary>Force a refresh of the local cached copy of the software.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _localCachedCopy;
    private bool _beginInterrupted;
    // $server is assigned only inside the ShouldProcess-gated connect (source :163-169) and read
    // unconditionally at $server.Databases[$Database] (:171). In the function it is function-scoped and
    // carries the PRIOR record's Server forward when a later record's connect gate returns false
    // (mixed interactive -Confirm across piped instances - codex-confirmed reachable). A per-record hop
    // resets it, so we carry it to reproduce that behavior. Starts null (never assigned on record 1).
    private object? _carriedServer;

    protected override void BeginProcessing()
    {
        bool completed = false;
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Force.ToBool(), LocalFile, Branch, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__InstallDarlingDataBeginComplete"]?.Value))
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
        if (_beginInterrupted || Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__InstallDarlingDataProcessComplete"]?.Value))
            {
                _carriedServer = UnwrapHopValue(item.Properties["Server"]?.Value);
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, Procedure, _localCachedCopy, Force.ToBool(),
            EnableException.ToBool(), this, _carriedServer,
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
param($Force, $LocalFile, $Branch, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param($Force, [string]$LocalFile, [string]$Branch, $EnableException, $__realCmdlet)

    if ($Force) { $ConfirmPreference = 'none' }

    # Do we need a new local cached version of the software?
    $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
    $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child "DarlingData-$Branch"
    if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
        if ($__realCmdlet.ShouldProcess('DarlingData', 'Update local cached copy of the software')) {
            try {
                Save-DbaCommunitySoftware -Software DarlingData -Branch $Branch -LocalFile $LocalFile -EnableException
            } catch {
                Stop-Function -Message 'Failed to update local cached copy' -ErrorRecord $_ -FunctionName Install-DbaDarlingData
            }
        }
    }

    [pscustomobject]@{ __InstallDarlingDataBeginComplete = $true; LocalCachedCopy = $localCachedCopy; Interrupted = [bool](Test-FunctionInterrupt) }
} $Force $LocalFile $Branch $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Procedure, $localCachedCopy, $Force, $EnableException, $__realCmdlet, $__carriedServer, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, $Database, [string[]]$Procedure, $localCachedCopy, $Force, $EnableException, $__realCmdlet, $__carriedServer)

    # -Force sets function-scoped $ConfirmPreference='none' in the SOURCE begin, which persists across
    # process records; separate hops don't share that scope, so re-establish it here (carried via $Force).
    if ($Force) { $ConfirmPreference = 'none' }
    # DEF-012 cross-record carrier: seed $server with the prior record's value BEFORE the loop so a
    # connect-gate-false record reads the stale $server exactly like the function scope does.
    $server = $__carriedServer
    . {
    if (Test-FunctionInterrupt) { return }

    foreach ($instance in $SqlInstance) {
        if ($__realCmdlet.ShouldProcess($instance, "Connecting to $instance")) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Install-DbaDarlingData
            }
        }

        $db = $server.Databases[$Database]
        if ($null -eq $db) {
            Stop-Function -Message "Database $Database not found on $instance. Skipping." -Target $instance -Continue -FunctionName Install-DbaDarlingData
        }

        if ($__realCmdlet.ShouldProcess($database, "Installing DarlingData procedures in $database on $instance")) {
            Write-Message -Level Verbose -Message "Starting installing/updating the DarlingData stored procedures in $database on $instance." -FunctionName Install-DbaDarlingData -ModuleName "dbatools"
            $allprocedures_query = "SELECT name FROM sys.procedures WHERE is_ms_shipped = 0"
            $allprocedures = ($server.Query($allprocedures_query, $Database)).Name

            if ($Procedure -contains "All") {
                # We install all scripts
                $sqlScripts = Get-ChildItem $localCachedCopy -Filter "DarlingData.sql" -Recurse
            } else {
                # We only install specific scripts that as located in different subdirectories and exclude the example
                $sqlScripts = @( )
                if ($Procedure -contains "Human" -or $Procedure -contains "HumanEvents") {
                    $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_HumanEvents.sql" -Recurse
                }
                if ($Procedure -contains "Pressure" -or $Procedure -contains "PressureDetector") {
                    $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_PressureDetector.sql" -Recurse
                }
                if ($Procedure -contains "Quickie" -or $Procedure -contains "QuickieStore") {
                    $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_QuickieStore.sql" -Recurse
                }
                if ($Procedure -contains "Block" -or $Procedure -contains "HumanEventsBlockViewer") {
                    $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_HumanEventsBlockViewer.sql" -Recurse
                }
                if ($Procedure -contains "Log" -or $Procedure -contains "LogHunter") {
                    $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_LogHunter.sql" -Recurse
                }
                if ($Procedure -contains "Health" -or $Procedure -contains "HealthParser") {
                    $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_HealthParser.sql" -Recurse
                }
                if ($Procedure -contains "Index" -or $Procedure -contains "IndexCleanup") {
                    $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_IndexCleanup.sql" -Recurse
                }
                if ($Procedure -contains "Perf" -or $Procedure -contains "PerfCheck") {
                    $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_PerfCheck.sql" -Recurse
                }
            }

            foreach ($script in $sqlScripts) {
                $sql = Get-Content $script.FullName -Raw
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

                if ($scriptName -eq "sp_QuickieStore.sql" -and ($server.VersionMajor -lt 13)) {
                    Write-Message -Level Warning -Message "$instance found to be below SQL Server 2016, skipping $scriptName" -FunctionName Install-DbaDarlingData -ModuleName "dbatools"
                    $baseres.Status = 'Skipped'
                    $baseres
                    continue
                }
                if ($__realCmdlet.ShouldProcess($instance, "installing/updating $scriptName in $database")) {
                    try {
                        # We use Invoke-DbaQuery because using ExecuteNonQuery with long batches causes problems on AppVeyor.
                        $null = Invoke-DbaQuery -SqlInstance $server -Database $Database -Query $sql -EnableException
                    } catch {
                        Write-Message -Level Warning -Message "Could not execute at least one portion of $scriptName in $Database on $instance." -ErrorRecord $_ -FunctionName Install-DbaDarlingData -ModuleName "dbatools"
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
        Write-Message -Level Verbose -Message "Finished installing/updating the DarlingData stored procedures in $database on $instance." -FunctionName Install-DbaDarlingData -ModuleName "dbatools"
    }
    }
    [pscustomobject]@{ __InstallDarlingDataProcessComplete = $true; Server = $server }
} $SqlInstance $SqlCredential $Database $Procedure $localCachedCopy $Force $EnableException $__realCmdlet $__carriedServer @__commonParameters 3>&1 2>&1
""";
}

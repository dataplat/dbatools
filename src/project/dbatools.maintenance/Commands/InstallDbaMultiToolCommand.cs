#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Installs or updates the DBA MultiTool stored procedures on target databases. The local-cache refresh,
/// per-instance connection, script execution, and ShouldProcess flow remain a module-scoped PowerShell
/// compatibility hop; this cmdlet supplies the real ShouldProcess runtime and preserves the advanced
/// function's begin/process lifetime. Surface pinned by migration/baselines/Install-DbaMultiTool.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Install, "DbaMultiTool", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class InstallDbaMultiToolCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The source branch of the DBA MultiTool repository.</summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    [ValidateSet("main", "development")]
    public string Branch { get; set; } = "main";

    /// <summary>The database to install the DBA MultiTool into.</summary>
    [Parameter(Position = 3)]
    public object Database { get; set; } = "master";

    /// <summary>Install from a local zip/folder instead of downloading.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string? LocalFile { get; set; }

    /// <summary>Force a refresh of the local cached copy of the software.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _localCachedCopy;
    private bool _beginInterrupted;

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
                item.Properties["__InstallMultiToolBeginComplete"]?.Value))
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

        // No cross-record carrier: $server's connect is NOT ShouldProcess-gated (source :152-156), so a
        // connect failure is Stop-Function -Continue-dominated and every $server read is same-record. Hence
        // no process-complete sentinel either (nothing to carry out), so a bare Invoke-DbaQuery's rows just
        // flow straight through WriteObject - no collision risk.
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
            SqlInstance, SqlCredential, Database, _localCachedCopy, Force.ToBool(),
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
    $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child "dba-multitool-$Branch"
    if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
        if ($__realCmdlet.ShouldProcess('DbaMultiTool', 'Update local cached copy of the software')) {
            try {
                Save-DbaCommunitySoftware -Software DbaMultiTool -Branch $Branch -LocalFile $LocalFile -EnableException
            } catch {
                Stop-Function -Message 'Failed to update local cached copy' -ErrorRecord $_ -FunctionName Install-DbaMultiTool
            }
        }
    }

    [pscustomobject]@{ __InstallMultiToolBeginComplete = $true; LocalCachedCopy = $localCachedCopy; Interrupted = [bool](Test-FunctionInterrupt) }
} $Force $LocalFile $Branch $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $localCachedCopy, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, $Database, $localCachedCopy, $Force, $EnableException, $__realCmdlet)

    # -Force sets function-scoped $ConfirmPreference='none' in the SOURCE begin, persisting across process
    # records; separate hops don't share that scope, so re-establish it here (T26, carried via $Force).
    if ($Force) { $ConfirmPreference = 'none' }

    if (Test-FunctionInterrupt) { return }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Install-DbaMultiTool
        }
        if ($__realCmdlet.ShouldProcess($Database, "Installing DbaMultiTool procedures in $Database on $instance")) {
            Write-Message -Level Verbose -Message "Starting installing/updating DbaMultiTool stored procedures in $Database on $instance." -FunctionName Install-DbaMultiTool -ModuleName "dbatools"
            $allProcedures_Query = "SELECT name FROM sys.procedures WHERE is_ms_shipped = 0;"
            $allProcedures = ($server.Query($allProcedures_Query, $Database)).Name

            # We only install specific scripts
            $sqlScripts = @( )
            $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_helpme.sql" -Recurse
            $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_doc.sql" -Recurse
            $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_sizeoptimiser.sql" -Recurse
            $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_estindex.sql" -Recurse
            $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_help_revlogin.sql" -Recurse

            foreach ($script in $sqlScripts) {
                $scriptName = $script.Name
                $scriptError = $false

                $baseRes = [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Database     = $Database
                    Name         = $script.BaseName
                    Status       = $null
                }
                if ($__realCmdlet.ShouldProcess($instance, "installing/updating $scriptName in $Database")) {
                    try {
                        Invoke-DbaQuery -SqlInstance $server -Database $Database -File $script.FullName -EnableException -Verbose:$false
                    } catch {
                        Write-Message -Level Warning -Message "Could not execute at least one portion of $scriptName in $Database on $instance." -ErrorRecord $_ -FunctionName Install-DbaMultiTool -ModuleName "dbatools"
                        $scriptError = $true
                    }

                    if ($scriptError) {
                        $baseRes.Status = 'Error'
                    } elseif ($script.BaseName -in $allProcedures) {
                        $baseRes.Status = 'Updated'
                    } else {
                        $baseRes.Status = 'Installed'
                    }
                    $baseRes
                }
            }
        }
        Write-Message -Level Verbose -Message "Finished installing/updating DbaMultiTool stored procedures in $Database on $instance." -FunctionName Install-DbaMultiTool -ModuleName "dbatools"
    }
} $SqlInstance $SqlCredential $Database $localCachedCopy $Force $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}

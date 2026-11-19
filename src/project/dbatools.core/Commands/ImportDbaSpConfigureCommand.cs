#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Copies sp_configure settings between instances or applies them from a SQL file. Port of
/// public/Import-DbaSpConfigure.ps1 (W3-057). Neither parameter set is pipeline-bound, so the
/// ENTIRE command (begin + process + end bodies, in source order) rides ONE VERBATIM module
/// hop per the no-pipeline convention (CopyDbaRegServer precedent): begin's connect/Test-SqlSa
/// guards whose Stop-Function+return short-circuit the concatenated process/end just as the
/// fn's Test-FunctionInterrupt guards did (the scope-1 magic-variable handshake rides verbatim
/// inside the single hop scope), then the process copy/apply body, then the end disconnect.
/// Two real sets (ServerCopy: Source/Destination/*SqlCredential; FromFile: SqlInstance/Path/
/// SqlCredential) plus the phantom Default set carrying only Force + inherited EnableException,
/// exactly as migration/baselines/Import-DbaSpConfigure.json pins them (no positions, no
/// aliases, no OutputType, ConfirmImpact Medium).
///
/// CARRIER (W2-170 class): the source's three branch selectors read $PSBoundParameters.Path
/// and $PSBoundParameters.Source as TRUTHINESS of the bound value (NOT Test-Bound boundness),
/// so they are carried as IsTrue-of-value flags $__boundPath / $__boundSource - matching the
/// source's own test line-by-line. A presence (ContainsKey) carrier would diverge on the
/// positional pass, where every arg is bound; -Path "" would wrongly select ServerCopy.
///
/// DEF-006: every hop-level Write-Message carries -FunctionName Import-DbaSpConfigure
/// -ModuleName "dbatools" (explicit -FunctionName suppresses frame auto-resolution, so
/// -ModuleName must be restored or it logs &lt;Unknown&gt;); every hop-level Stop-Function
/// carries -FunctionName Import-DbaSpConfigure (Stop-Function is excluded from the -ModuleName
/// axis by ruling). There are no helper functions, so every attribution site is hop-level.
///
/// DEF-001: begin's Stop-Function -Continue throws under -EnableException (a mid-body
/// terminating throw), so the buffered foreach would lose emitted output - delivered via
/// InvokeScopedStreaming, the streaming graft.
/// </summary>
[Cmdlet("Import", "DbaSpConfigure", DefaultParameterSetName = "Default", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class ImportDbaSpConfigureCommand : DbaBaseCmdlet
{
    /// <summary>Source SQL Server instance to copy sp_configure settings from.</summary>
    [Parameter(ParameterSetName = "ServerCopy")]
    public DbaInstanceParameter? Source { get; set; }

    /// <summary>Target SQL Server instance where sp_configure settings will be applied.</summary>
    [Parameter(ParameterSetName = "ServerCopy")]
    public DbaInstanceParameter? Destination { get; set; }

    /// <summary>Credential for connecting to the source instance.</summary>
    [Parameter(ParameterSetName = "ServerCopy")]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>Credential for connecting to the destination instance.</summary>
    [Parameter(ParameterSetName = "ServerCopy")]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>SQL Server instance to set up sp_configure values on from a SQL file.</summary>
    [Parameter(ParameterSetName = "FromFile")]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Path to a SQL script file containing sp_configure commands to execute.</summary>
    [Parameter(ParameterSetName = "FromFile")]
    public string? Path { get; set; }

    /// <summary>Credential for connecting to the target instance when applying from a file.</summary>
    [Parameter(ParameterSetName = "FromFile")]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Bypasses the SQL Server version compatibility check between source and destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
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
        }, BodyScript,
            Source, Destination, SourceSqlCredential, DestinationSqlCredential,
            SqlInstance, Path, SqlCredential, Force.ToBool(), EnableException.ToBool(),
            BoundTruthy("Source"), BoundTruthy("Path"),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    /// <summary>Carries a $PSBoundParameters.X TRUTHINESS read (W2-170 class): IsTrue of the
    /// bound value, or false when unbound (an absent key reads as $null - falsy).</summary>
    private object? BoundTruthy(string name)
    {
        if (MyInvocation.BoundParameters.TryGetValue(name, out object? value))
            return LanguagePrimitives.IsTrue(value);
        return false;
    }

    // PS: begin body then process body then end body VERBATIM (single hop; no pipeline
    // parameters means process runs once). Substitutions only: the three $PSBoundParameters
    // truthiness selectors become the carried $__boundPath / $__boundSource flags, and
    // hop-level Write-Message / Stop-Function calls gain explicit -FunctionName (Write-Message
    // also -ModuleName "dbatools") per DEF-006.
    private const string BodyScript = """
param($Source, $Destination, $SourceSqlCredential, $DestinationSqlCredential, $SqlInstance, $Path, $SqlCredential, $Force, $EnableException, $__boundSource, $__boundPath, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Destination, [PSCredential]$SourceSqlCredential, [PSCredential]$DestinationSqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [string]$Path, [PSCredential]$SqlCredential, $Force, $EnableException, $__boundSource, $__boundPath, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (-not $__boundPath -and $__boundSource) {
        try {
            $sourceserver = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source -FunctionName Import-DbaSpConfigure
            return
        }

        if (-not (Test-SqlSa -SqlInstance $sourceserver -SqlCredential $SourceSqlCredential)) {
            Stop-Function -Message "Not a sysadmin on $sourceserver. Quitting." -Category PermissionDenied -Target $server -Continue -FunctionName Import-DbaSpConfigure
        }

        try {
            $destserver = Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination -FunctionName Import-DbaSpConfigure
            return
        }

        if (-not (Test-SqlSa -SqlInstance $destserver -SqlCredential $DestinationSqlCredential)) {
            Stop-Function -Message "Not a sysadmin on $destserver. Quitting." -Category PermissionDenied -Target $server -Continue -FunctionName Import-DbaSpConfigure
        }

        $source = $sourceserver.DomainInstanceName
        $destination = $destserver.DomainInstanceName
    } else {
        try {
            $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -FunctionName Import-DbaSpConfigure
            return
        }

        if (!(Test-SqlSa -SqlInstance $server -SqlCredential $SqlCredential)) {
            Stop-Function -Message "Not a sysadmin on $server. Quitting." -Category PermissionDenied -Target $server -Continue -FunctionName Import-DbaSpConfigure
        }

        if (-not (Test-Path $Path)) {
            Stop-Function -Message "File $Path Not Found" -Category InvalidArgument -Target $Path -Continue -FunctionName Import-DbaSpConfigure
        }
    }

    if ($Force) { $ConfirmPreference = 'none' }

    if (Test-FunctionInterrupt) { return }
    if (-not $__boundPath) {
        if ($Pscmdlet.ShouldProcess($destination, "Export sp_configure")) {
            $sqlfilename = Export-DbaSpConfigure $sourceserver
        }

        # The source's process-block `return` exits only the process block - end{} still runs
        # (disconnects + completion message). In this CONCATENATED hop a bare return would skip
        # the appended end body, so the mismatch case sets a skip flag and falls through (codex).
        $__skipProcessRemainder = $false
        if ($sourceserver.versionMajor -ne $destserver.versionMajor -and $force -eq $false) {
            Write-Message -Level Warning -Message "Source SQL Server major version and Destination SQL Server major version must match for sp_configure migration. Use -Force to override this precaution or check the exported sql file, $sqlfilename, and run manually." -FunctionName Import-DbaSpConfigure -ModuleName "dbatools"
            $__skipProcessRemainder = $true
        }

        If ((-not $__skipProcessRemainder) -and $Pscmdlet.ShouldProcess($destination, "Execute sp_configure")) {
            $sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
            $sourceserver.Configuration.Alter($true)
            $destserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
            $sourceserver.Configuration.Alter($true)

            $destprops = $destserver.Configuration.Properties

            foreach ($sourceprop in $sourceserver.Configuration.Properties) {
                $displayname = $sourceprop.DisplayName

                $destprop = $destprops | Where-Object { $_.Displayname -eq $displayname }
                if ($null -ne $destprop) {
                    try {
                        $destprop.configvalue = $sourceprop.configvalue
                        $null = $destserver.Query("RECONFIGURE WITH OVERRIDE")
                        Write-Message -Level Output -Message "updated $($destprop.displayname) to $($sourceprop.configvalue)." -FunctionName Import-DbaSpConfigure -ModuleName "dbatools"
                    } catch {
                        Stop-Function -Message "Could not set $($destprop.displayname) to $($sourceprop.configvalue). Feature may not be supported." -ErrorRecord $_ -Continue -FunctionName Import-DbaSpConfigure
                    }
                }
            }
            try {
                $destserver.Configuration.Alter()
            } catch {
                $needsrestart = $true
            }

            $sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $false
            $sourceserver.Configuration.Alter($true)
            $destserver.Configuration.ShowAdvancedOptions.ConfigValue = $false
            $destserver.Configuration.Alter($true)

            if ($needsrestart -eq $true) {
                Write-Message -Level Warning -Message "Some configuration options will be updated once SQL Server is restarted." -FunctionName Import-DbaSpConfigure -ModuleName "dbatools"
            } else {
                Write-Message -Level Output -Message "Configuration option has been updated." -FunctionName Import-DbaSpConfigure -ModuleName "dbatools"
            }
        }

        # Also inside the skip gate: the mismatch path's warning points the user at the
        # exported SQL for manual use - the function world's return preserved it (codex r2).
        if ((-not $__skipProcessRemainder) -and $Pscmdlet.ShouldProcess($destination, "Removing temp file")) {
            Remove-Item $sqlfilename -ErrorAction SilentlyContinue
        }

    } else {
        if ($Pscmdlet.ShouldProcess($destination, "Importing sp_configure from $Path")) {
            $server.Configuration.ShowAdvancedOptions.ConfigValue = $true
            $sql = Get-Content $Path
            foreach ($line in $sql) {
                try {
                    $null = $server.Query($line)
                    Write-Message -Level Output -Message "Successfully executed $line." -FunctionName Import-DbaSpConfigure -ModuleName "dbatools"
                } catch {
                    Stop-Function -Message "$line failed. Feature may not be supported." -ErrorRecord $_ -Continue -FunctionName Import-DbaSpConfigure
                }
            }
            $server.Configuration.ShowAdvancedOptions.ConfigValue = $false
            Write-Message -Level Warning -Message "Some configuration options will be updated once SQL Server is restarted." -FunctionName Import-DbaSpConfigure -ModuleName "dbatools"
        }
    }

    if (Test-FunctionInterrupt) { return }

    if ($__boundPath) {
        $server.ConnectionContext.Disconnect()
    } else {
        $sourceserver.ConnectionContext.Disconnect()
        $destserver.ConnectionContext.Disconnect()
    }

    If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) {
        Write-Message -Level Output -Message "SQL Server configuration options migration finished." -FunctionName Import-DbaSpConfigure -ModuleName "dbatools"
    }
} $Source $Destination $SourceSqlCredential $DestinationSqlCredential $SqlInstance $Path $SqlCredential $Force $EnableException $__boundSource $__boundPath $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports sp_configure settings to a .sql script. Port of
/// public/Export-DbaSpConfigure.ps1 (W3-017). Three blocks: the begin block runs
/// Test-ExportDirectory ONCE (a directory-prep side effect, no cross-block state), the process
/// block does the per-instance work, and the end block writes a single verbose message - so the
/// port keeps them as three hops (BeginProcessing / ProcessRecord / EndProcessing). Only the
/// process hop STREAMS (DEF-001 cond1+cond2: it emits Get-ChildItem per instance AND has reachable
/// Stop-Function -Continue at Connect-DbaInstance / the show-advanced-options and file writes); the
/// begin and end hops emit nothing so their throw semantics are DEF-001-neutral. The source reads
/// $PSBoundParameters.Path / $PSBoundParameters.FilePath (the EXPLICITLY bound values, null when
/// unbound) to drive Get-ExportFilePath's naming, distinct from the defaulted $Path used by
/// Test-ExportDirectory - so both bound values are carried verbatim (null when unbound) and $Path's
/// runtime default (Get-DbatoolsConfigValue 'Path.DbatoolsExport') is re-applied in the begin hop.
/// No ShouldProcess. Substitutions only: $PSBoundParameters.Path/.FilePath -> the carried bound
/// values, explicit -FunctionName Export-DbaSpConfigure on Stop-Function (W1-090); the body is
/// otherwise verbatim. Surface pinned by migration/baselines/Export-DbaSpConfigure.json.
/// </summary>
[Cmdlet(VerbsData.Export, "DbaSpConfigure")]
public sealed class ExportDbaSpConfigureCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Directory for the exported script (defaults to the configured export path).</summary>
    [Parameter(Position = 2)]
    public string? Path { get; set; }

    /// <summary>Explicit output file path.</summary>
    [Parameter(Position = 3)]
    [Alias("OutFile", "FileName")]
    public string? FilePath { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void BeginProcessing()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BeginScript,
            BoundValue("Path"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

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
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, BoundValue("Path"), BoundValue("FilePath"), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, EndScript,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private object? BoundValue(string name)
    {
        return MyInvocation.BoundParameters.TryGetValue(name, out object? value) ? value : null;
    }

    // PS: the begin block. $Path's runtime default (Get-DbatoolsConfigValue) is re-applied when the
    // parameter was not bound, then Test-ExportDirectory runs ONCE. Verbatim otherwise.
    private const string BeginScript = """
param($__pathBound, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__pathBound, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $Path = if ($null -ne $__pathBound) { $__pathBound } else { Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport' }
    $null = Test-ExportDirectory -Path $Path
} $__pathBound $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process body VERBATIM per record. Substitutions only: $PSBoundParameters.Path /
    // $PSBoundParameters.FilePath -> the carried bound values ($__pathBound / $__filePathBound,
    // null when unbound), explicit -FunctionName Export-DbaSpConfigure on Stop-Function (W1-090).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $__pathBound, $__filePathBound, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, $__pathBound, $__filePathBound, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # Named-wrapper shim: the process body runs inside a function carrying the command's name,
    # so call-stack-deriving helpers see Export-DbaSpConfigure exactly as in the function world -
    # Get-ExportFilePath builds the export filename from (Get-PSCallStack)[1].Command, and the
    # anonymous scriptblock frame otherwise put a literal <scriptblock> marker in the filename.
    # The dot-sourced invocation keeps the body in the hop scope, so the interrupt latch and
    # any cross-record state behave unchanged.
    function Export-DbaSpConfigure {
    if (Test-FunctionInterrupt) { return }
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Export-DbaSpConfigure
        }

        $FilePath = Get-ExportFilePath -Path $__pathBound -FilePath $__filePathBound -Type sql -ServerName $instance
        $ShowAdvancedOptions = $server.Configuration.ShowAdvancedOptions.ConfigValue

        if ($ShowAdvancedOptions -eq 0) {
            try {
                $server.Configuration.ShowAdvancedOptions.ConfigValue = $true
                $server.Configuration.Alter($true)
            } catch {
                Stop-Function -Message "Can't set 'show advanced options' to 1 on instance $instance" -ErrorRecord $_ -Continue -FunctionName Export-DbaSpConfigure
            }
        }

        try {
            Set-Content -Path $FilePath "EXEC sp_configure 'show advanced options' , 1;  RECONFIGURE WITH OVERRIDE"
        } catch {
            Stop-Function -Message "Can't write to $FilePath" -ErrorRecord $_ -Continue -FunctionName Export-DbaSpConfigure
        }

        foreach ($sourceprop in $server.Configuration.Properties) {
            $displayname = $sourceprop.DisplayName
            $configvalue = $sourceprop.ConfigValue
            Add-Content -Path $FilePath "EXEC sp_configure '$displayname' , $configvalue;"
        }

        if ($ShowAdvancedOptions -eq 0) {
            Add-Content -Path $FilePath "EXEC sp_configure 'show advanced options' , 0;"
            Add-Content -Path $FilePath "RECONFIGURE WITH OVERRIDE"

            $server.Configuration.ShowAdvancedOptions.ConfigValue = $false
            $server.Configuration.Alter($true)
        }
        Get-ChildItem -Path $FilePath
    }
    }
    . Export-DbaSpConfigure
} $SqlInstance $SqlCredential $__pathBound $__filePathBound $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the end block. Verbatim.
    private const string EndScript = """
param($__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    Write-Message -Level Verbose -Message "Server configuration export finished" -FunctionName Export-DbaSpConfigure -ModuleName "dbatools"
} $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

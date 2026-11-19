#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Generates T-SQL scripts to recreate SQL Server replication distributor and publication
/// configurations. Port of public/Export-DbaReplServerSetting.ps1. The whole command body rides
/// ONE VERBATIM module hop per pipeline record: the begin-block Add-ReplicationLibrary /
/// Test-ExportDirectory, the foreach over SqlInstance, the still-module-scope Get-DbaReplServer
/// lookup, and the per-server Get-ExportFilePath / .Script() / Passthru-or-Out-File emit. The
/// command has no ShouldProcess, so no real-cmdlet routing is needed. The source's
/// $PSBoundParameters.Path / .FilePath reads (the caller-bound values, NULL when the caller relied
/// on the -Path default) are carried as the $__boundPath / $__boundFilePath flags computed from the
/// real cmdlet's MyInvocation.BoundParameters, since a hop always receives parameters positionally
/// and could not otherwise tell whether the caller supplied them; the default-resolved $Path is
/// used only for the begin-block Test-ExportDirectory, exactly as the source separates them.
/// In-hop Stop-Function/Write-Message carry -FunctionName and read $EnableException from the hop
/// param scope; merged-back 6..2&gt;&amp;1 records re-emit via the host warning/error streams
/// (InvokeScopedStreaming), so -WarningVariable capture matches the function world. No cross-record
/// state (each record is self-contained; the one Stop-Function is -Continue, which does not latch).
/// ACCEPTED DEVIATION: Get-ExportFilePath derives the auto-generated file name's caller token from
/// (Get-PSCallStack)[1]; through the hop that frame is the module scriptblock rather than the public
/// function, so the cosmetic "-replication" token in an auto-named file drops. It affects only the
/// on-disk file name of the non-Passthru path, whose .Script() output requires native RMO and is
/// itself DEFERRED-TO-REPL-HARNESS. Surface pinned by migration/baselines/Export-DbaReplServerSetting.json.
/// </summary>
[Cmdlet(VerbsData.Export, "DbaReplServerSetting")]
[Alias("Export-DbaRepServerSetting")]
public sealed class ExportDbaReplServerSettingCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The directory where the replication script file will be created. Defaults to the dbatools export path configuration.</summary>
    [Parameter(Position = 2)]
    public string? Path { get; set; }

    /// <summary>The complete file path including filename for the exported replication script. Overrides Path and default naming.</summary>
    [Parameter(Position = 3)]
    [Alias("OutFile", "FileName")]
    public string? FilePath { get; set; }

    /// <summary>Custom Microsoft.SqlServer.Replication.ScriptOptions flags controlling which replication components are scripted.</summary>
    [Parameter(Position = 4)]
    public object[]? ScriptOption { get; set; }

    /// <summary>Replication server objects from Get-DbaReplServer pipeline input for batch processing.</summary>
    [Parameter(Position = 5, ValueFromPipeline = true)]
    public object[]? InputObject { get; set; }

    /// <summary>The character encoding for the output script file. Defaults to UTF8.</summary>
    [Parameter(Position = 6)]
    [ValidateSet("ASCII", "BigEndianUnicode", "Byte", "String", "Unicode", "UTF7", "UTF8", "Unknown")]
    public string Encoding { get; set; } = "UTF8";

    /// <summary>Returns the generated T-SQL replication script to the pipeline instead of writing to a file.</summary>
    [Parameter]
    public SwitchParameter Passthru { get; set; }

    /// <summary>Prevents overwriting an existing file with the same name.</summary>
    [Parameter]
    public SwitchParameter NoClobber { get; set; }

    /// <summary>Adds the replication script to the end of an existing file instead of overwriting it.</summary>
    [Parameter]
    public SwitchParameter Append { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
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
        SqlInstance, SqlCredential, Path, FilePath, ScriptOption, InputObject, Encoding,
            Passthru.ToBool(), NoClobber.ToBool(), Append.ToBool(), EnableException.ToBool(),
            MyInvocation.BoundParameters.ContainsKey("Path"),
            MyInvocation.BoundParameters.ContainsKey("FilePath"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // The whole command body VERBATIM in the dbatools module scope: the begin-block library load
    // and export-directory test, the per-instance foreach, the still-PS Get-DbaReplServer, and the
    // per-server Get-ExportFilePath / .Script() / Passthru-or-Out-File emit. Stop-Function/
    // Write-Message carry -FunctionName. $PSBoundParameters.Path/.FilePath parity is the carried
    // $__boundPath / $__boundFilePath flags.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Path, $FilePath, $ScriptOption, $InputObject, $Encoding, $Passthru, $NoClobber, $Append, $EnableException, $__boundPath, $__boundFilePath, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    # Passthru/NoClobber/Append are passed positionally as plain booleans, NOT [switch]: under
    # [CmdletBinding()] a [switch] param takes no positional slot, so typing them would shift every
    # trailing positional argument by one and overflow the last slot ('argument False' bind error).
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string]$Path, [string]$FilePath, [object[]]$ScriptOption, [object[]]$InputObject, [string]$Encoding, $Passthru, $NoClobber, $Append, $EnableException, $__boundPath, $__boundFilePath)

    # $PSBoundParameters.Path / .FilePath parity: the source composes the export file path from the
    # CALLER-BOUND values (null when the caller relied on the -Path default), while the begin-block
    # Test-ExportDirectory uses the default-resolved $Path.
    $__pathBound = if ($__boundPath) { $Path } else { $null }
    $__filePathBound = if ($__boundFilePath) { $FilePath } else { $null }
    if (-not $__boundPath) { $Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport') }

    Add-ReplicationLibrary
    $null = Test-ExportDirectory -Path $Path

    if (Test-FunctionInterrupt) { return }
    foreach ($instance in $SqlInstance) {
        $InputObject += Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException
    }

    foreach ($repserver in $InputObject) {
        $FilePath = Get-ExportFilePath -Path $__pathBound -FilePath $__filePathBound -Type sql -ServerName $repserver.SqlServerName

        try {
            if (-not $ScriptOption) {
                $out = $repserver.Script(
                    [Microsoft.SqlServer.Replication.ScriptOptions]::Creation -bor
                    [Microsoft.SqlServer.Replication.ScriptOptions]::IncludeAll -bor
                    [Microsoft.SqlServer.Replication.ScriptOptions]::EnableReplicationDB -bor
                    [Microsoft.SqlServer.Replication.ScriptOptions]::IncludeInstallDistributor)
            } else {
                $out = $repserver.Script($scriptOption)
            }
        } catch {
            Stop-Function -ErrorRecord $_ -Message "Replication export failed. Is it setup?" -Continue -FunctionName Export-DbaReplServerSetting
        }
        if ($Passthru) {
            "exec sp_dropdistributor @no_checks = 1, @ignore_distributor = 1" | Out-String
            $out | Out-String
            continue
        }

        "exec sp_dropdistributor @no_checks = 1, @ignore_distributor = 1" | Out-File -FilePath $FilePath -Encoding $encoding -Append
        $out | Out-File -FilePath $FilePath -Encoding $encoding -Append:$Append
    }
} $SqlInstance $SqlCredential $Path $FilePath $ScriptOption $InputObject $Encoding $Passthru $NoClobber $Append $EnableException $__boundPath $__boundFilePath @__commonParameters 3>&1 2>&1
""";
}

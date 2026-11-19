#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Generates an Azure Data Studio diagnostic-queries Jupyter notebook. Port of
/// public/New-DbaDiagnosticAdsNotebook.ps1 (W1-111). The whole process body rides ONE
/// VERBATIM module hop: the two validation gates with their INTERPOLATED-variable
/// messages (both-empty renders the double-space "At least one of  and  must be
/// provided"), the Invoke-DbaQuery version detection with the $versions lookup and the
/// 2016 SP2 append, the $script:PSModuleRoot diagnosticquery file probe, the private
/// Invoke-DbaDiagnosticQueryScriptParser walk building $cells, the ConvertTo-Json -Depth
/// 3 serialization, the [IO.File]::WriteAllLines CWD-relative write (statement-faults
/// continue to the next statement exactly as the function's did) and the Get-ChildItem
/// location-relative emission. SupportsShouldProcess is DECLARED but never consulted -
/// -WhatIf still writes the file, exactly like the function. In-hop Stop-Functions carry
/// -FunctionName (W1-090); EE throws propagate out of the hop uncaught (the function's
/// terminating path); merged-back 2&gt;&amp;1 records re-emit through WriteError with
/// the W1-045 silent-bag compensation. Surface pinned by
/// migration/baselines/New-DbaDiagnosticAdsNotebook.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaDiagnosticAdsNotebook", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaDiagnosticAdsNotebookCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance. Defaults to the default instance on localhost.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The SQL Server version to generate diagnostic queries for.</summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    [ValidateSet("2005", "2008", "2008R2", "2012", "2014", "2016", "2016SP2", "2017", "2019", "2022", "AzureSQLDatabase")]
    public string? TargetVersion { get; set; }

    /// <summary>The full file path where the notebook will be created.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [PsStringCast]
    public string Path { get; set; } = null!;

    /// <summary>Include database-level diagnostic queries too.</summary>
    [Parameter]
    public SwitchParameter IncludeDatabaseSpecific { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        // PS: an unbound [String] parameter reads "" (W1-087), never null.
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BodyScript,
            SqlInstance, SqlCredential, TargetVersion ?? "", Path,
            IncludeDatabaseSpecific.ToBool(), EnableException.ToBool(), BoundVerbose(), BoundDebug()))
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
        }
    }

    /// <summary>A bound -Debug carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundDebug()
    {
        object? debug;
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    /// <summary>A bound -Verbose carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundVerbose()
    {
        object? verbose;
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    // PS: the whole process body VERBATIM in the dbatools module scope (in-hop
    // Stop-Functions carry -FunctionName per W1-090; EE rides as a hop param that
    // Stop-Function resolves dynamically).
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $TargetVersion, $Path, $IncludeDatabaseSpecific, $EnableException, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($SqlInstance, $SqlCredential, $TargetVersion, $Path, $IncludeDatabaseSpecific, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    # validate input parameters: you cannot provide $TargetVersion and $SqlInstance
    # together. If you specify a SqlInstance, version will be determined from metadata
    if (-not $TargetVersion -and -not $SqlInstance) {
        Stop-Function -Message "At least one of $SqlInstance and $TargetVersion must be provided" -FunctionName New-DbaDiagnosticAdsNotebook
        return
    } elseif ((-not (-not $TargetVersion)) -and -not (-not $SqlInstance)) {
        Stop-Function -Message "Cannot provide both $SqlInstance and $TargetVersion" -FunctionName New-DbaDiagnosticAdsNotebook
        return
    }

    if (-not $TargetVersion) {
        $versionQuery = "
            SELECT SERVERPROPERTY('ProductMajorVersion') AS ProductMajorVersion,
                   SERVERPROPERTY('ProductMinorVersion') AS ProductMinorVersion,
                   SERVERPROPERTY('ProductLevel') AS ProductLevel,
                   SERVERPROPERTY('Edition') AS Edition"

        $versions = @{
            "9.0"   = "2005"
            "10.0"  = "2008"
            "10.50" = "2008R2"
            "11.0"  = "2012"
            "12.0"  = "2014"
            "13.0"  = "2016"
            "14.0"  = "2017"
            "15.0"  = "2019"
            "16.0"  = "2022"
        }

        try {
            $ServerInfo = Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Query $versionQuery
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -FunctionName New-DbaDiagnosticAdsNotebook
            return
        }

        if ($ServerInfo.Edition -eq "SQL Azure") {
            $TargetVersion = "AzureSQLDatabase"
        } else {
            $TargetVersion = $versions["$($ServerInfo.ProductMajorVersion).$($ServerInfo.ProductMinorVersion)"]

            if ($TargetVersion -eq "2016" -and $ServerInfo.ProductLevel -eq "SP2") {
                $TargetVersion += "SP2"
            }
        }
    }

    # $script:PSModuleRoot can resolve empty under the Pester harness (Invoke-ManualPester,
    # the RB-IMP-51 class), which turns the script path rootless. Fall back to the live
    # module's base path, the same defensive pattern as Invoke-DbaDiagnosticQuery.
    $moduleRoot = $script:PSModuleRoot
    if (-not $moduleRoot) {
        $moduleRoot = (Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1).ModuleBase
    }
    $diagnosticScriptPath = Get-ChildItem -Path "$moduleRoot\bin\diagnosticquery\" -Filter "SQLServerDiagnosticQueries_$($TargetVersion).sql" | Select-Object -First 1

    if (-not $diagnosticScriptPath) {
        Stop-Function -Message "No diagnostic queries available for `$TargetVersion = $TargetVersion" -FunctionName New-DbaDiagnosticAdsNotebook
        return
    }

    $cells = @()

    Invoke-DbaDiagnosticQueryScriptParser $diagnosticScriptPath.FullName | Where-Object { -not $_.DBSpecific -or $IncludeDatabaseSpecific } | ForEach-Object {
        $cells += @{cell_type = "markdown"; source = "## $($_.QueryName)`n`n$($_.Description)"; metadata = "" }
        $cells += @{cell_type = "code"; source = $_.Text; metadata = "" }
    }

    $outputObject = @{
        metadata       = @{
            kernelspec    = @{
                name         = "SQL"
                display_name = "SQL"
                language     = "sql"
            }
            language_info = @{
                name    = "sql"
                version = ""
            }
        }
        nbformat_minor = 2
        nbformat       = 4
        cells          = $cells
    }

    [IO.File]::WriteAllLines($Path, (ConvertTo-Json -InputObject $outputObject -Depth 3))
    Get-ChildItem -Path $Path
} $SqlInstance $SqlCredential $TargetVersion $Path $IncludeDatabaseSpecific $EnableException $__boundVerbose $__boundDebug 3>&1 2>&1
""";
}

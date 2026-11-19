#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Compares a source DACPAC to a target database or DACPAC via sqlpackage DeployReport. Port of
/// public/Compare-DbaDbSchema.ps1; the workflow remains a module-scoped PowerShell compatibility
/// hop.
///
/// This is a BEGIN+PROCESS command, so it ships as TWO hops. The begin block runs once (resolve
/// sqlpackage, validate the mutually-exclusive target parameters, prepare the export directory);
/// the process block runs per pipeline record (build the sqlpackage arguments, optionally connect,
/// shell out, parse the deployment-report XML, emit one object per operation item). Folding begin
/// into the first record would re-run the validation and its warnings on every record, so the split
/// is required for parity.
///
/// INTERRUPT CARRY. Stop-Function sets a module interrupt flag in ITS CALLER's scope, and
/// Test-FunctionInterrupt reads it at the caller's scope. Within one function scope that spans
/// begin and every process block, a failure halts the rest; across two separate module-scope hop
/// invocations the flag does not survive, so it is carried explicitly. After each hop body (dot-
/// sourced so the source's early returns exit only the body while the sentinel still emits) the hop
/// reads the interrupt variable at Get-Variable -Scope 0 - which sees a Stop-Function called
/// DIRECTLY in the body but NOT one buried in a nested helper, exactly as the function-scope
/// Test-FunctionInterrupt would. This reproduces a measured source asymmetry: a begin VALIDATION
/// failure (direct Stop-Function) interrupts process so it emits nothing, but sqlpackage-not-found
/// (Get-DbaSqlPackagePath's INTERNAL Stop-Function, then begin's bare return) does NOT interrupt -
/// the source runs process with a null path and fails per-record in the sqlpackage try/catch. Every
/// process Stop-Function is a "+ return" with no -Continue, so a failure on one record halts later
/// records too; that interrupt is carried record-to-record through the process sentinel.
///
/// OutputPath's source default is (Get-DbatoolsConfigValue Path.DbatoolsExport), a config lookup
/// that a C# property initializer cannot carry without a side-effecting default (DEF-007). The begin
/// hop reproduces the bind-time default instead: when -OutputPath was not bound it resolves the
/// config value, then carries the resolved OutputPath (with $sqlPackagePath) to the process hop, so
/// both blocks see the one value the source binds once.
///
/// The body's single Connect-DbaInstance sits in a try/catch that throws-catches-StopFunction on
/// failure, so a bare in-hop connect is faithful and no NestedConnect is needed (its nested-warning
/// parity concern is for a connect that WARNS without throwing while the function surfaces both
/// streams - not this shape).
///
/// No ShouldProcess (the source declares none). In-hop Stop-Function/Write-Message carry
/// -FunctionName because Stop-Function defaults it from Get-PSCallStack and the hop's frame is
/// generated script; the calls INSIDE Get-DbaSqlPackagePath keep that helper's own attribution and
/// are not stamped. Surface pinned by migration/baselines/Compare-DbaDbSchema.json.
/// </summary>
[Cmdlet(VerbsData.Compare, "DbaDbSchema")]
public sealed class CompareDbaDbSchemaCommand : DbaBaseCmdlet
{
    /// <summary>The source DACPAC file path.</summary>
    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, Position = 0)]
    [Alias("Path", "FilePath")]
    [PsStringCast]
    public string SourcePath { get; set; } = null!;

    /// <summary>The target SQL Server instance.</summary>
    [Parameter(Position = 1)]
    public DbaInstanceParameter? TargetSqlInstance { get; set; }

    /// <summary>Alternative credential for the target instance.</summary>
    [Parameter(Position = 2)]
    public PSCredential? TargetSqlCredential { get; set; }

    /// <summary>The target database name (with -TargetSqlInstance).</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    public string? TargetDatabase { get; set; }

    /// <summary>The target DACPAC file path (instead of a live instance).</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string? TargetPath { get; set; }

    /// <summary>The directory for the deployment-report XML; defaults to the DbatoolsExport config
    /// path, resolved in the begin hop.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    public string? OutputPath { get; set; }

    /// <summary>Keep the deployment-report XML instead of deleting it.</summary>
    [Parameter]
    public SwitchParameter KeepReport { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Begin-block results carried to the process hop: the resolved sqlpackage path and OutputPath.
    private string? _sqlPackagePath;
    private string? _resolvedOutputPath;
    // The function-scope interrupt: set by a direct begin Stop-Function (validation gates), or by a
    // process Stop-Function on an earlier record. Either halts the remaining process records.
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        // Begin runs before pipeline binding, so clone the bound parameters for the bound flags.
        Hashtable bound = new Hashtable(MyInvocation.BoundParameters);
        bool boundOutputPath = bound.ContainsKey("OutputPath");
        bool boundTargetSqlInstance = bound.ContainsKey("TargetSqlInstance");
        bool boundTargetPath = bound.ContainsKey("TargetPath");
        bool boundTargetDatabase = bound.ContainsKey("TargetDatabase");

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            TargetSqlInstance, TargetDatabase, TargetPath, OutputPath, EnableException.ToBool(),
            boundOutputPath, boundTargetSqlInstance, boundTargetPath, boundTargetDatabase,
            BoundCommonParameter("Verbose"), BoundCommonParameter("Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__compareDbaDbSchemaBegin"))
            {
                if (sentinel["__compareDbaDbSchemaBegin"] is Hashtable state)
                {
                    _sqlPackagePath = CarriedString(state["SqlPackagePath"]);
                    _resolvedOutputPath = CarriedString(state["OutputPath"]);
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
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SourcePath, TargetSqlInstance, TargetSqlCredential, TargetDatabase, TargetPath,
            _resolvedOutputPath, KeepReport.ToBool(), _sqlPackagePath, EnableException.ToBool(),
            BoundCommonParameter("TargetSqlInstance"),
            BoundCommonParameter("Verbose"), BoundCommonParameter("Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__compareDbaDbSchemaProcess"))
            {
                if (sentinel["__compareDbaDbSchemaProcess"] is Hashtable state)
                {
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

    /// <summary>Reads a string carried back through the begin sentinel. Values the hop produced by
    /// calling PowerShell functions (Get-DbaSqlPackagePath, Get-DbatoolsConfigValue) arrive
    /// PSObject-wrapped and "as string" on the wrapper yields null, silently dropping the carry -
    /// unwrap first. Null stays null: the sqlpackage-not-found asymmetry needs a genuinely absent
    /// path to reach the process block unchanged.</summary>
    private static string? CarriedString(object? value) =>
        (value is PSObject wrapped ? wrapped.BaseObject : value) as string;

    /// <summary>Carries a bound common parameter (or the TargetSqlInstance bound flag) into the hop
    /// scopes, which cannot see the caller's $PSBoundParameters. Null means the caller never bound
    /// it.</summary>
    private object? BoundCommonParameter(string name)
    {
        if (MyInvocation.BoundParameters.TryGetValue(name, out object? value))
        {
            // -Verbose/-Debug carry their truthiness; a plain bound flag (TargetSqlInstance) carries
            // the fact it was bound.
            return name is "Verbose" or "Debug" ? LanguagePrimitives.IsTrue(value) : true;
        }
        return null;
    }

    // PS: the begin block VERBATIM, dot-sourced so its early returns exit only the block. Edits:
    // Test-Bound -> carried flags, -FunctionName on the direct Stop-Functions, and the OutputPath
    // bind-time default when -OutputPath was not bound. The sentinel reports $sqlPackagePath, the
    // resolved $OutputPath, and whether a DIRECT begin Stop-Function set the function-scope
    // interrupt (Get-Variable -Scope 0 sees the body's own Stop-Function, not the one inside
    // Get-DbaSqlPackagePath).
    private const string BeginScript = """
param($TargetSqlInstance, $TargetDatabase, $TargetPath, $OutputPath, $EnableException, $__boundOutputPath, $__boundTargetSqlInstance, $__boundTargetPath, $__boundTargetDatabase, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$TargetSqlInstance, [string]$TargetDatabase, [string]$TargetPath, [string]$OutputPath, $EnableException, $__boundOutputPath, $__boundTargetSqlInstance, $__boundTargetPath, $__boundTargetDatabase, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # OutputPath bind-time default: the source binds (Get-DbatoolsConfigValue Path.DbatoolsExport)
    # when -OutputPath is not supplied; the C# surface cannot carry a config-derived default.
    if (-not $__boundOutputPath) {
        $OutputPath = Get-DbatoolsConfigValue -FullName "Path.DbatoolsExport"
    }

    . {
        $sqlPackagePath = Get-DbaSqlPackagePath -EnableException:$EnableException
        if (-not $sqlPackagePath) {
            return
        }

        if ((-not $__boundTargetSqlInstance) -and (-not $__boundTargetPath)) {
            Stop-Function -Message "You must specify either -TargetSqlInstance (with -TargetDatabase) or -TargetPath." -FunctionName Compare-DbaDbSchema
            return
        }

        if (($__boundTargetSqlInstance) -and ($__boundTargetPath)) {
            Stop-Function -Message "Specify either -TargetSqlInstance or -TargetPath, not both." -FunctionName Compare-DbaDbSchema
            return
        }

        if ($__boundTargetSqlInstance) {
            if (-not $__boundTargetDatabase) {
                Stop-Function -Message "When using -TargetSqlInstance you must also specify -TargetDatabase." -FunctionName Compare-DbaDbSchema
                return
            }
        }

        if ($__boundTargetPath) {
            if (-not (Test-Path -Path $TargetPath)) {
                Stop-Function -Message "Target DACPAC file not found: $TargetPath" -FunctionName Compare-DbaDbSchema
                return
            }
        }

        $null = Test-ExportDirectory -Path $OutputPath
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __compareDbaDbSchemaBegin = @{ SqlPackagePath = $sqlPackagePath; OutputPath = $OutputPath; Interrupted = [bool]($__iv -and $__iv.Value) } }
} $TargetSqlInstance $TargetDatabase $TargetPath $OutputPath $EnableException $__boundOutputPath $__boundTargetSqlInstance $__boundTargetPath $__boundTargetDatabase $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM, dot-sourced so its early returns exit only the block. Edits:
    // Test-Bound TargetSqlInstance -> carried flag, -FunctionName on the direct Stop-Function/
    // Write-Message. $sqlPackagePath and $OutputPath are the carried begin results. The sentinel
    // reports whether this record's body set the function-scope interrupt (a "+ return"
    // Stop-Function), so a failure here halts later records as the single function scope would.
    // The sqlpackage argument string contains runs of three double-quotes (a PS escaped-quote pair
    // immediately followed by the string's closing quote), so this raw string uses a FOUR-quote
    // delimiter - a three-quote delimiter would be closed early by that content.
    private const string ProcessScript = """"
param($SourcePath, $TargetSqlInstance, $TargetSqlCredential, $TargetDatabase, $TargetPath, $OutputPath, $KeepReport, $sqlPackagePath, $EnableException, $__boundTargetSqlInstance, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$SourcePath, [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$TargetSqlInstance, [PSCredential]$TargetSqlCredential, [string]$TargetDatabase, [string]$TargetPath, [string]$OutputPath, $KeepReport, $sqlPackagePath, $EnableException, $__boundTargetSqlInstance, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if (Test-FunctionInterrupt) { return }

        if (-not (Test-Path -Path $SourcePath)) {
            Stop-Function -Message "Source DACPAC file not found: $SourcePath" -FunctionName Compare-DbaDbSchema
            return
        }

        $sourcePathFull = (Resolve-Path -Path $SourcePath).ProviderPath
        $timeStamp = (Get-Date).ToString("yyMMdd_HHmmss_f")
        $reportFile = Join-Path -Path $OutputPath -ChildPath "Compare-DbaDbSchema_$timeStamp.xml"

        # Build sqlpackage arguments
        $sqlPackageArgs = "/action:deployreport /of:True /sf:""$sourcePathFull"" /op:""$reportFile"""

        if ($__boundTargetSqlInstance) {
            try {
                $targetServer = Connect-DbaInstance -SqlInstance $TargetSqlInstance -SqlCredential $TargetSqlCredential
            } catch {
                Stop-Function -Message "Failure connecting to $TargetSqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $TargetSqlInstance -FunctionName Compare-DbaDbSchema
                return
            }

            $connString = $targetServer.ConnectionContext.ConnectionString | Convert-ConnectionString
            if ($connString -notmatch "Database=") {
                $connString = "$connString;Database=$TargetDatabase"
            }
            $connStringEscaped = $connString.Replace('"', "'")
            $sqlPackageArgs += " /tcs:""$connStringEscaped"""
            $targetDescription = "$($targetServer.DomainInstanceName)\$TargetDatabase"
        } else {
            $targetPathFull = (Resolve-Path -Path $TargetPath).ProviderPath
            $targetDbName = [System.IO.Path]::GetFileNameWithoutExtension($TargetPath)
            $sqlPackageArgs += " /tf:""$targetPathFull"" /tdn:""$targetDbName"""
            $targetDescription = $TargetPath
        }

        Write-Message -Level Verbose -Message "Running sqlpackage DeployReport for $sourcePathFull against $targetDescription." -FunctionName Compare-DbaDbSchema -ModuleName "dbatools"

        try {
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $sqlPackagePath
            $startInfo.Arguments = $sqlPackageArgs
            $startInfo.RedirectStandardError = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $startInfo
            $process.Start() | Out-Null
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()

            Write-Message -Level Verbose -Message "sqlpackage stdout: $stdout" -FunctionName Compare-DbaDbSchema -ModuleName "dbatools"

            if ($process.ExitCode -ne 0) {
                Stop-Function -Message "sqlpackage failed: $stderr" -Target $SourcePath -FunctionName Compare-DbaDbSchema
                return
            }
        } catch {
            Stop-Function -Message "Failed to run sqlpackage" -ErrorRecord $_ -Target $SourcePath -FunctionName Compare-DbaDbSchema
            return
        }

        if (-not (Test-Path -Path $reportFile)) {
            Stop-Function -Message "sqlpackage did not produce an output report at $reportFile. Output: $stdout" -FunctionName Compare-DbaDbSchema
            return
        }

        # Parse the deployment report XML
        try {
            [xml]$report = Get-Content -Path $reportFile -ErrorAction Stop
        } catch {
            Stop-Function -Message "Failed to read or parse the deployment report at $reportFile" -ErrorRecord $_ -Target $reportFile -FunctionName Compare-DbaDbSchema
            return
        }

        foreach ($operation in $report.DeploymentReport.Operations.Operation) {
            $operationName = $operation.Name
            foreach ($item in $operation.Item) {
                $objectType = $item.Type -replace "^Sql", ""
                $outputObject = [PSCustomObject]@{
                    SourcePath = $sourcePathFull
                    Target     = $targetDescription
                    Operation  = $operationName
                    Value      = $item.Value
                    Type       = $objectType
                }

                if ($KeepReport) {
                    $outputObject | Add-Member -NotePropertyName "ReportPath" -NotePropertyValue $reportFile
                }

                $outputObject
            }
        }

        if (-not $KeepReport) {
            Remove-Item -Path $reportFile -ErrorAction SilentlyContinue
        } else {
            Write-Message -Level Verbose -Message "Deployment report kept at $reportFile" -FunctionName Compare-DbaDbSchema -ModuleName "dbatools"
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __compareDbaDbSchemaProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $SourcePath $TargetSqlInstance $TargetSqlCredential $TargetDatabase $TargetPath $OutputPath $KeepReport $sqlPackagePath $EnableException $__boundTargetSqlInstance $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
"""";
}

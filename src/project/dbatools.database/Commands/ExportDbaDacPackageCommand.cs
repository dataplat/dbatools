#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports a database to a .dacpac or .bacpac. Port of public/Export-DbaDacPackage.ps1; the
/// workflow remains a module-scoped PowerShell compatibility hop.
///
/// A BEGIN+PROCESS hop (SqlInstance is ValueFromPipeline, so process fires per record) with two
/// mechanisms no earlier dbatools.database row needed:
///
/// 1. $PSCmdlet.ParameterSetName is read to branch SMO (DacFx API) vs CMD (sqlpackage.exe). The inner
///    hop scriptblock cannot resolve the caller's set (all params from both sets are passed
///    positionally), so the real cmdlet's ParameterSetName is carried as a string and each
///    $PSCmdlet.ParameterSetName replaced by $__parameterSetName.
/// 2. Get-ExportFilePath derives the export-file token from (Get-PSCallStack)[1].Command
///    (.Replace("Export-Dba","").ToLower() = "dacpackage"). Called bare from the hop, frame 1 is the
///    generated scriptblock, so the call is routed through a named wrapper function
///    Export-DbaDacPackage inside the hop - the RestartDbaService attribution-shim pattern - so the
///    caller frame carries the right name.
///
/// Begin validates the export directory and, in the CMD set, that sqlpackage is available (a direct
/// Stop-Function, no -Continue, sets the interrupt); begin sets $sqlPackagePath but the process block
/// re-derives it, so nothing but the interrupt carries begin-to-process. The process block also
/// carries its own interrupt record-to-record: its top validations are Stop-Function+return with no
/// -Continue, so a failure on one record must silence later records. Both carries use the
/// Get-Variable -Scope 0 sentinel; C# gates each block. Path's config default
/// (Get-DbatoolsConfigValue Path.DbatoolsExport) is reproduced in begin when -Path is unbound;
/// $PSBoundParameters.Path/.FilePath are bound-value reads carried as raw values; the one Test-Bound
/// (Database/ExcludeDatabase/AllUserDatabases) rides carried flags. There is no ShouldProcess.
///
/// Surface pinned by migration/baselines/Export-DbaDacPackage.json (two sets SMO/CMD, DefaultSet SMO).
/// </summary>
[Cmdlet(VerbsData.Export, "DbaDacPackage", DefaultParameterSetName = "SMO")]
public sealed class ExportDbaDacPackageCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to export.</summary>
    [Parameter]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Export all user databases.</summary>
    [Parameter]
    public SwitchParameter AllUserDatabases { get; set; }

    /// <summary>The output directory; defaults to the DbatoolsExport config path.</summary>
    [Parameter]
    [PsStringCast]
    public string? Path { get; set; }

    /// <summary>The output file path.</summary>
    [Parameter]
    [Alias("OutFile", "FileName")]
    [PsStringCast]
    public string? FilePath { get; set; }

    /// <summary>A DacExtractOptions/DacExportOptions object (SMO set).</summary>
    [Parameter(ParameterSetName = "SMO")]
    [Alias("ExtractOptions", "ExportOptions", "DacExtractOptions", "DacExportOptions", "Options", "Option")]
    public object? DacOption { get; set; }

    /// <summary>Extra sqlpackage command-line parameters (CMD set).</summary>
    [Parameter(ParameterSetName = "CMD")]
    [PsStringCast]
    public string? ExtendedParameters { get; set; }

    /// <summary>Extra sqlpackage properties (CMD set).</summary>
    [Parameter(ParameterSetName = "CMD")]
    [PsStringCast]
    public string? ExtendedProperties { get; set; }

    /// <summary>Dacpac or Bacpac.</summary>
    [Parameter]
    [ValidateSet("Dacpac", "Bacpac")]
    [PsStringCast]
    public string Type { get; set; } = "Dacpac";

    /// <summary>The table(s) to include (SMO set).</summary>
    [Parameter(ParameterSetName = "SMO")]
    [PsStringArrayCast]
    public string[]? Table { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Whether begin's CMD-set sqlpackage validation set the interrupt, and whether an earlier
    // process record's top-validation Stop-Function+return did - either silences later records.
    private bool _beginInterrupted;
    private bool _processInterrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable beginState && beginState.ContainsKey("__exportDbaDacPackageBegin"))
            {
                if (beginState["__exportDbaDacPackageBegin"] is Hashtable state)
                {
                    _beginInterrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                }
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BeginScript,
            Path, TestBound(nameof(Path)), ParameterSetName, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _beginInterrupted || _processInterrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable procState && procState.ContainsKey("__exportDbaDacPackageProcess"))
            {
                if (procState["__exportDbaDacPackageProcess"] is Hashtable state)
                {
                    _processInterrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                }
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, AllUserDatabases.ToBool(), Path,
            FilePath, DacOption, ExtendedParameters, ExtendedProperties, Type, Table,
            EnableException.ToBool(), ParameterSetName,
            TestBound(nameof(Database)), TestBound(nameof(ExcludeDatabase)), TestBound(nameof(AllUserDatabases)),
            TestBound(nameof(Path)) ? (object?)Path : null, TestBound(nameof(FilePath)) ? (object?)FilePath : null,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block VERBATIM. Edits: $PSCmdlet.ParameterSetName -> $__parameterSetName and
    // -FunctionName on the direct Stop-Function. The config-default Path is reproduced when -Path was
    // not bound. The sentinel reports whether the CMD-set validation set the function-scope interrupt.
    private const string BeginScript = """
param($Path, $__boundPath, $__parameterSetName, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$Path, $__boundPath, $__parameterSetName, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # Path bind-time default: the source binds (Get-DbatoolsConfigValue Path.DbatoolsExport) when
    # -Path is not supplied; the C# surface cannot carry a config-derived default.
    if (-not $__boundPath) {
        $Path = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'
    }

    . {
        $null = Test-ExportDirectory -Path $Path

        # For CMD parameter set (ExtendedParameters/ExtendedProperties), we need SqlPackage.exe
        # For SMO parameter set (default), we use the DacFx API from dbatools.library
        if ($__parameterSetName -eq 'CMD') {
            $sqlPackagePath = Get-DbaSqlPackagePath
            if (-not $sqlPackagePath) {
                Stop-Function -Message "SqlPackage.exe is required when using -ExtendedParameters or -ExtendedProperties. Install it using Install-DbaSqlPackage or use the default DacFx API mode without these parameters." -FunctionName Export-DbaDacPackage
                return
            }
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __exportDbaDacPackageBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $Path $__boundPath $__parameterSetName $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM, dot-sourced so its early returns exit only the block while the
    // interrupt sentinel still emits. Edits: $PsCmdlet.ParameterSetName -> $__parameterSetName; the
    // one Test-Bound -> carried flags; $PSBoundParameters.Path/.FilePath -> carried bound values; the
    // Get-ExportFilePath call routed through the named wrapper Export-DbaDacPackage; -FunctionName on
    // direct Stop-Function/Write-Message.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $AllUserDatabases, $Path, $FilePath, $DacOption, $ExtendedParameters, $ExtendedProperties, $Type, $Table, $EnableException, $__parameterSetName, $__boundDatabase, $__boundExcludeDatabase, $__boundAllUserDatabases, $__boundPathValue, $__boundFilePathValue, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(DefaultParameterSetName = "SMO")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, $AllUserDatabases, [string]$Path, [string]$FilePath, [object]$DacOption, [string]$ExtendedParameters, [string]$ExtendedProperties, [string]$Type, [string[]]$Table, $EnableException, $__parameterSetName, $__boundDatabase, $__boundExcludeDatabase, $__boundAllUserDatabases, $__boundPathValue, $__boundFilePathValue, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # ATTRIBUTION SHIM (the Get-PSCallStack class): Get-ExportFilePath derives its export-file token
    # from (Get-PSCallStack)[1].Command. Called bare from this hop, frame 1 is the hop scriptblock;
    # this named wrapper puts "Export-DbaDacPackage" in frame 1 exactly like the source's own frame.
    function Export-DbaDacPackage {
        param($Path, $FilePath, $Type, $ServerName, $DatabaseName)
        Get-ExportFilePath -Path $Path -FilePath $FilePath -Type $Type -ServerName $ServerName -DatabaseName $DatabaseName
    }

    . {
        if (Test-FunctionInterrupt) { return }

        if ((-not $__boundDatabase) -and (-not $__boundExcludeDatabase) -and (-not $__boundAllUserDatabases)) {
            Stop-Function -Message "You must specify databases to execute against using either -Database, -ExcludeDatabase or -AllUserDatabases" -FunctionName Export-DbaDacPackage
            return
        }

        #check that at least one of the DB selection parameters was specified
        if (!$AllUserDatabases -and !$Database) {
            Stop-Function -Message "Either -Database or -AllUserDatabases should be specified" -Continue -FunctionName Export-DbaDacPackage
        }
        #Check Option object types - should have a specific type
        if ($Type -eq 'Dacpac') {
            if ($DacOption -and $DacOption -isnot [Microsoft.SqlServer.Dac.DacExtractOptions]) {
                Stop-Function -Message "Microsoft.SqlServer.Dac.DacExtractOptions object type is expected - got $($DacOption.GetType())." -FunctionName Export-DbaDacPackage
                return
            }
        } elseif ($Type -eq 'Bacpac') {
            if ($DacOption -and $DacOption -isnot [Microsoft.SqlServer.Dac.DacExportOptions]) {
                Stop-Function -Message "Microsoft.SqlServer.Dac.DacExportOptions object type is expected - got $($DacOption.GetType())." -FunctionName Export-DbaDacPackage
                return
            }
        }

        #Create a tuple to be used as a table filter
        if ($Table) {
            $tblList = New-Object 'System.Collections.Generic.List[Tuple[String, String]]'
            foreach ($tableItem in $Table) {
                # Use Get-ObjectNameParts to correctly handle bracketed names like [Gross.Table.Name]
                $nameParts = Get-ObjectNameParts -ObjectName $tableItem
                if (-not $nameParts.Parsed -or -not $nameParts.Name) {
                    Stop-Function -Message "Table value '$tableItem' is not a valid one-, two-, or three-part name. Use bracket quoting for names that contain periods." -FunctionName Export-DbaDacPackage
                    return
                }
                if ($nameParts.Schema) {
                    $schemaName = $nameParts.Schema
                } else {
                    $schemaName = "dbo"
                }
                $tblList.Add((New-Object "tuple[String, String]" -ArgumentList $schemaName, $nameParts.Name))
            }
        } else {
            $tblList = $null
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Export-DbaDacPackage
            }

            # Check SQL Server version - DAC Framework requires SQL Server 2008 R2+ (Version 10.50+)
            if ($server.VersionMajor -lt 10 -or ($server.VersionMajor -eq 10 -and $server.VersionMinor -lt 50)) {
                Stop-Function -Message "Export-DbaDacPackage requires SQL Server 2008 R2 or higher (DAC Framework minimum version 10.50). Server $instance is version $($server.VersionString)." -Target $instance -Continue -FunctionName Export-DbaDacPackage
            }

            # ============================================================
            # THREAD-SAFE DATABASE ENUMERATION
            # Use Invoke-DbaQuery instead of Get-DbaDatabase to avoid SMO thread-safety issues
            # Get-DbaDatabase uses $server.Databases enumeration which is NOT thread-safe in parallel runspaces
            # Note: Export-DbaDacPackage requires SQL Server 2008 R2+ (DAC Framework minimum version)
            # ============================================================

            # Build query to enumerate databases (equivalent to Get-DbaDatabase -OnlyAccessible -ExcludeSystem)
            $query = @"
SELECT name
FROM sys.databases
WHERE database_id > 4  -- Exclude system databases (master=1, tempdb=2, model=3, msdb=4)
  AND state = 0        -- Only ONLINE databases (OnlyAccessible equivalent)
"@

            $sqlParams = @{ }

            # Add ExcludeDatabase filter if specified (using parameterized queries to prevent SQL injection)
            if ($ExcludeDatabase) {
                $placeholders = @()
                for ($i = 0; $i -lt $ExcludeDatabase.Count; $i++) {
                    $placeholders += "@exclude$i"
                    $sqlParams["exclude$i"] = $ExcludeDatabase[$i]
                }
                $query += "`n  AND name NOT IN ($($placeholders -join ','))"
            }

            $query += "`nORDER BY name"

            Write-Message -Level Verbose -Message "Executing query: $query" -FunctionName Export-DbaDacPackage -ModuleName "dbatools"

            $splatQuery = @{
                SqlInstance     = $server
                Query           = $query
                EnableException = $true
            }
            if ($sqlParams.Count -gt 0) {
                $splatQuery.SqlParameter = $sqlParams
            }

            $dbNames = Invoke-DbaQuery @splatQuery | Select-Object -ExpandProperty name

            # Apply Database filter if specified
            if ($Database) {
                $dbNames = $dbNames | Where-Object { $_ -in $Database }
            }

            if (-not $dbNames) {
                Stop-Function -Message "Databases not found on $instance" -Target $instance -Continue -FunctionName Export-DbaDacPackage
            }

            Write-Message -Level Verbose -Message "Found $($dbNames.Count) databases: $($dbNames -join ", ")" -FunctionName Export-DbaDacPackage -ModuleName "dbatools"

            # Convert database names to objects for compatibility with rest of function
            $dbs = $dbNames | ForEach-Object { [PSCustomObject]@{ name = $_ } }

            foreach ($db in $dbs) {
                $resultstime = [diagnostics.stopwatch]::StartNew()
                $dbName = $db.name
                $connstring = $server.ConnectionContext.ConnectionString | Convert-ConnectionString
                if ($connstring -notmatch 'Database=') {
                    $connstring = "$connstring;Database=$dbName"
                }

                Write-Message -Level Verbose -Message "Using connection string $connstring" -FunctionName Export-DbaDacPackage -ModuleName "dbatools"

                if ($Type -eq 'Dacpac') {
                    $ext = 'dacpac'
                } elseif ($Type -eq 'Bacpac') {
                    $ext = 'bacpac'
                }

                $FilePath = Export-DbaDacPackage -Path $__boundPathValue -FilePath $__boundFilePathValue -Type $ext -ServerName $instance -DatabaseName $dbName

                #using DacFx API by default
                if ($__parameterSetName -eq 'SMO') {
                    try {
                        $dacSvc = New-Object -TypeName Microsoft.SqlServer.Dac.DacServices -ArgumentList $connstring -ErrorAction Stop
                    } catch {
                        Stop-Function -Message "Could not connect to the connection string $connstring" -Target $instance -Continue -FunctionName Export-DbaDacPackage
                    }
                    if (-not $DacOption) {
                        $opts = New-DbaDacOption -Type $Type -Action Export
                    } else {
                        $opts = $DacOption
                    }

                    $null = $output = Register-ObjectEvent -InputObject $dacSvc -EventName "Message" -SourceIdentifier "msg" -Action { $EventArgs.Message.Message }

                    if ($Type -eq 'Dacpac') {
                        Write-Message -Level Verbose -Message "Initiating Dacpac extract to $FilePath" -FunctionName Export-DbaDacPackage -ModuleName "dbatools"
                        #not sure how to extract that info from the existing DAC application, leaving 1.0.0.0 for now
                        $version = New-Object System.Version -ArgumentList '1.0.0.0'
                        try {
                            $dacSvc.Extract($FilePath, $dbName, $dbName, $version, $null, $tblList, $opts, $null)
                        } catch {
                            Stop-Function -Message "DacServices extraction failure" -ErrorRecord $_ -Continue -FunctionName Export-DbaDacPackage
                        } finally {
                            Unregister-Event -SourceIdentifier "msg"
                        }
                    } elseif ($Type -eq 'Bacpac') {
                        Write-Message -Level Verbose -Message "Initiating Bacpac export to $FilePath" -FunctionName Export-DbaDacPackage -ModuleName "dbatools"
                        try {
                            $dacSvc.ExportBacpac($FilePath, $dbName, $opts, $tblList, $null)
                        } catch {
                            Stop-Function -Message "DacServices export failure" -ErrorRecord $_ -Continue -FunctionName Export-DbaDacPackage
                        } finally {
                            Unregister-Event -SourceIdentifier "msg"
                        }
                    }
                    $finalResult = ($output.output -join [System.Environment]::NewLine | Out-String).Trim()
                } elseif ($__parameterSetName -eq 'CMD') {
                    if ($Type -eq 'Dacpac') { $action = 'Extract' }
                    elseif ($Type -eq 'Bacpac') { $action = 'Export' }
                    $cmdConnString = $connstring.Replace('"', "'")

                    $sqlPackageArgs = "/action:$action /tf:""$FilePath"" /SourceConnectionString:""$cmdConnString"" $ExtendedParameters $ExtendedProperties"

                    try {
                        $startprocess = New-Object System.Diagnostics.ProcessStartInfo

                        $sqlpackage = Get-DbaSqlPackagePath
                        if ($sqlpackage) {
                            $startprocess.FileName = $sqlpackage
                        } else {
                            Stop-Function -Message "SqlPackage not found. Please install SqlPackage using Install-DbaSqlPackage or ensure it's available in PATH." -Continue -FunctionName Export-DbaDacPackage
                        }
                        $startprocess.Arguments = $sqlPackageArgs
                        $startprocess.RedirectStandardError = $true
                        $startprocess.RedirectStandardOutput = $true
                        $startprocess.UseShellExecute = $false
                        $startprocess.CreateNoWindow = $true
                        $process = New-Object System.Diagnostics.Process
                        $process.StartInfo = $startprocess
                        $process.Start() | Out-Null
                        $stdout = $process.StandardOutput.ReadToEnd()
                        $stderr = $process.StandardError.ReadToEnd()
                        $process.WaitForExit()
                        Write-Message -level Verbose -Message "StandardOutput: $stdout" -FunctionName Export-DbaDacPackage -ModuleName "dbatools"
                        $finalResult = $stdout
                    } catch {
                        Stop-Function -Message "SQLPackage Failure" -ErrorRecord $_ -Continue -FunctionName Export-DbaDacPackage
                    }

                    if ($process.ExitCode -ne 0) {
                        Stop-Function -Message "Standard output - $stderr" -Continue -FunctionName Export-DbaDacPackage
                    }
                }
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Database     = $dbName
                    Path         = $FilePath
                    Elapsed      = [prettytimespan]($resultstime.Elapsed)
                    Result       = $finalResult
                } | Select-DefaultView -ExcludeProperty ComputerName, InstanceName
            }
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __exportDbaDacPackageProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $AllUserDatabases $Path $FilePath $DacOption $ExtendedParameters $ExtendedProperties $Type $Table $EnableException $__parameterSetName $__boundDatabase $__boundExcludeDatabase $__boundAllUserDatabases $__boundPathValue $__boundFilePathValue $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

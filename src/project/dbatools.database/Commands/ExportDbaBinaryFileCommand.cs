#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports binary/image column data from database tables to files. Port of
/// public/Export-DbaBinaryFile.ps1; the workflow remains a module-scoped PowerShell compatibility
/// hop.
///
/// This is a BEGIN+PROCESS command shipped as two hops, because InputObject is ValueFromPipeline so
/// process fires per record. The begin block validates the mutually-exclusive -Path/-FilePath and
/// creates the -Path directory once; it sets nothing the process block reads, so it carries only
/// whether its two direct Stop-Function validation gates set the function-scope interrupt (detected
/// with Get-Variable -Scope 0 after the body, exactly as the function-scope Test-FunctionInterrupt
/// would see it). C# stores that and short-circuits ProcessRecord. There is no process-to-process
/// carry: the one non--Continue process Stop-Function ("Failed to get tables") sits in the
/// "if (-not $InputObject)" branch, which fires only in the non-piped single-record case, so its
/// return just ends that one record.
///
/// The begin hop carries -WhatIf/-Confirm and its inner block is SupportsShouldProcess, because the
/// begin block's New-Item honors those preferences in the source (the function is
/// SupportsShouldProcess, so -WhatIf/-Confirm set the preference New-Item inherits) - without the
/// carry the port would create the -Path directory under -WhatIf.
///
/// The process body reads $PSBoundParameters.Query/FileNameColumn/BinaryColumn/FilePath - a TRUTHINESS test of the bound VALUE (W2-071 fix:
/// reads that cannot ride a hop, because inside the hop $PSBoundParameters is the inner
/// scriptblock's own positional binding where every parameter looks bound. They are carried as
/// flags from C# (MyInvocation.BoundParameters.ContainsKey) and each $PSBoundParameters.X is
/// carried as the raw VALUE via BoundRaw, so -not $PSBoundParameters.X becomes -not on the value - was boundness/Test-Bound, which diverged on a bound-but-falsy value like -Query "".
///
/// The single $Pscmdlet.ShouldProcess routes to the real cmdlet via $__realCmdlet (ConfirmImpact
/// Medium); -WhatIf/-Confirm ride the carriers. In-hop Stop-Function/Write-Message carry
/// -FunctionName. Surface pinned by migration/baselines/Export-DbaBinaryFile.json (no parameter
/// sets; the source declares no explicit positions, so PowerShell auto-numbers every non-switch
/// parameter 0-10 in declaration order - those implicit positions are made explicit here).
/// </summary>
[Cmdlet(VerbsData.Export, "DbaBinaryFile", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class ExportDbaBinaryFileCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>The table(s) to export from.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Table { get; set; }

    /// <summary>The schema(s) to limit to.</summary>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? Schema { get; set; }

    /// <summary>The column holding the file name.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    public string? FileNameColumn { get; set; }

    /// <summary>The column holding the binary data.</summary>
    [Parameter(Position = 6)]
    [PsStringCast]
    public string? BinaryColumn { get; set; }

    /// <summary>The output directory.</summary>
    [Parameter(Position = 7)]
    [PsStringCast]
    public string? Path { get; set; }

    /// <summary>A custom query supplying the file name and binary columns.</summary>
    [Parameter(Position = 8)]
    [PsStringCast]
    public string? Query { get; set; }

    /// <summary>The output file path.</summary>
    [Parameter(Position = 9)]
    [Alias("OutFile", "FileName")]
    [PsStringCast]
    public string? FilePath { get; set; }

    /// <summary>Table object(s), typically from Get-DbaDbTable.</summary>
    [Parameter(ValueFromPipeline = true, Position = 10)]
    public Microsoft.SqlServer.Management.Smo.Table[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Whether a begin validation gate set the function-scope interrupt (the source's begin block
    // Stop-Functions have no -Continue, so process must emit nothing after a bad -Path/-FilePath).
    private bool _beginInterrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__exportDbaBinaryFileBegin"))
            {
                if (sentinel["__exportDbaBinaryFileBegin"] is Hashtable state)
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
            Path, FilePath, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _beginInterrupted)
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
            SqlInstance, SqlCredential, Database, Table, Schema, FileNameColumn, BinaryColumn,
            Path, Query, FilePath, InputObject, EnableException.ToBool(),
            BoundRaw("Query"), BoundRaw("FileNameColumn"), BoundRaw("BinaryColumn"),
            BoundRaw("FilePath"),
            this, NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private object? BoundRaw(string name)
    {
        if (MyInvocation.BoundParameters.TryGetValue(name, out object? value))
            return value;
        return null;
    }

    // PS: the begin block VERBATIM. Edits: -FunctionName on the direct Stop-Function/Write-Message.
    // The sentinel reports whether a direct begin Stop-Function set the function-scope interrupt.
    private const string BeginScript = """
param($Path, $FilePath, $EnableException, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Path, [string]$FilePath, $EnableException, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if ($Path -and $FilePath) {
            Stop-Function -Message "You cannot specify both -Path and -FilePath" -FunctionName Export-DbaBinaryFile
        }

        if (-not $Path -and -not $FilePath) {
            Stop-Function -Message "You must specify either -Path or -FilePath" -FunctionName Export-DbaBinaryFile
        }
        if ($Path) {
            if (-not (Test-Path -Path $Path -PathType Container)) {
                Write-Message -Level Verbose -Message "Creating path $Path" -FunctionName Export-DbaBinaryFile -ModuleName "dbatools"
                $null = New-Item -Path $Path -ItemType Directory -Force
            }
        }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __exportDbaBinaryFileBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $Path $FilePath $EnableException $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM. Edits: $Pscmdlet.ShouldProcess -> $__realCmdlet, -FunctionName
    // on direct Stop-Function/Write-Message, and each $PSBoundParameters.X TRUTHINESS read replaced by
    // its carried raw VALUE via BoundRaw ($__boundQuery/$__boundFileNameColumn/$__boundBinaryColumn/$__boundFilePath).
    // The ExecuteReader binary-stream loop, the filestream/binarywriter, and the finally ride as-is.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Table, $Schema, $FileNameColumn, $BinaryColumn, $Path, $Query, $FilePath, $InputObject, $EnableException, $__boundQuery, $__boundFileNameColumn, $__boundBinaryColumn, $__boundFilePath, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Table, [string[]]$Schema, [string]$FileNameColumn, [string]$BinaryColumn, [string]$Path, [string]$Query, [string]$FilePath, [Microsoft.SqlServer.Management.Smo.Table[]]$InputObject, $EnableException, $__boundQuery, $__boundFileNameColumn, $__boundBinaryColumn, $__boundFilePath, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if (Test-FunctionInterrupt) { return }
        if (-not $InputObject) {
            try {
                $InputObject = Get-DbaDbTable -SqlInstance $SqlInstance -Database $Database -Table $Table -Schema $Schema -SqlCredential $SqlCredential -EnableException
            } catch {
                Stop-Function -Message "Failed to get tables" -ErrorRecord $PSItem -FunctionName Export-DbaBinaryFile
                return
            }
        }

        Write-Message -Level Verbose -Message "Found $($InputObject.count) tables" -FunctionName Export-DbaBinaryFile -ModuleName "dbatools"
        foreach ($tbl in $InputObject) {
            # auto detect column that is binary
            # if none or multiple, make them specify the binary column
            # auto detect column that is a name
            # if none or multiple, make them specify the filename column or extension
            $server = $tbl.Parent.Parent
            $db = $tbl.Parent

            if (-not $__boundQuery) {
                if (-not $__boundFileNameColumn) {
                    $FileNameColumn = ($tbl.Columns | Where-Object Name -Match Name).Name
                    if ($FileNameColumn.Count -gt 1) {
                        Stop-Function -Message "Multiple column names match the phrase 'name' in $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name). Please specify the column to use with -FileNameColumn" -Continue -FunctionName Export-DbaBinaryFile
                    }
                    if ($FileNameColumn.Count -eq 0) {
                        Stop-Function -Message "No column names match the phrase 'name' in $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name). Please specify the column to use with -FileNameColumn" -Continue -FunctionName Export-DbaBinaryFile
                    }
                }

                if (-not $__boundBinaryColumn) {
                    $BinaryColumn = ($tbl.Columns | Where-Object { $PSItem.DataType.Name -match "binary" -or $PSItem.DataType.Name -eq "image" }).Name
                    if ($BinaryColumn.Count -gt 1) {
                        Stop-Function -Message "Multiple columns have a binary datatype in $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name). Please specify the column to use with -BinaryColumn" -Continue -FunctionName Export-DbaBinaryFile
                    }
                    if ($BinaryColumn.Count -eq 0) {
                        Stop-Function -Message "No columns have a binary datatype in $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name). Please specify the column to use with -BinaryColumn" -Continue -FunctionName Export-DbaBinaryFile
                    }
                }
            }

            # Stream buffer size in bytes.
            $bufferSize = 8192
            if (-not $__boundQuery) {
                $Query = "SELECT [$FileNameColumn], [$BinaryColumn] FROM $db.$tbl"
            }
            <#
                INSERT INTO [test].[dbo].[MyTable] ([FileName], TheFile)
                SELECT 'BackupCert.cer', * FROM OPENROWSET(BULK N'C:\temp\BackupCert.cer', SINGLE_BLOB) rs
            #>
            try {
                Write-Message -Level Verbose -Message "Query: $Query" -FunctionName Export-DbaBinaryFile -ModuleName "dbatools"
                $reader = $server.ConnectionContext.ExecuteReader($Query)

                # Create a byte array for the stream.
                $out = [array]::CreateInstance('Byte', $bufferSize)

                # Looping through records
                while ($reader.Read()) {
                    if (-not $__boundFilePath -and $Path) {
                        $FilePath = Join-Path -Path $Path -ChildPath (Split-Path -Path $reader.GetString(0) -Leaf)
                    }

                    if ($__realCmdlet.ShouldProcess($env:computername, "Exporting $FilePath from $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name)")) {
                        # New BinaryWriter
                        $filestream = New-Object System.IO.FileStream $FilePath, Create, Write
                        $binarywriter = New-Object System.IO.BinaryWriter $filestream

                        $start = 0
                        # Read first byte stream
                        $received = $reader.GetBytes(1, $start, $out, 0, $bufferSize - 1)
                        while ($received -gt 0) {
                            $binarywriter.Write($out, 0, $received)
                            $binarywriter.Flush()
                            $start += $received
                            # Read next byte stream
                            $received = $reader.GetBytes(1, $start, $out, 0, $bufferSize - 1)
                        }

                        $filestream.Close()
                        $filestream.Dispose()
                        $binarywriter.Close()
                        $binarywriter.Dispose()

                        Get-ChildItem -Path $FilePath
                    }
                }
                $reader.Close()
            } catch {
                Stop-Function -Message "Failed to export binary file from $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name)" -ErrorRecord $PSItem -Continue -FunctionName Export-DbaBinaryFile
            } finally {
                if (-not $reader.IsClosed ) {
                    $reader.Close()
                }
                if ($filestream.CanRead) {
                    $filestream.Close()
                    $filestream.Dispose()
                }
                if ($binarywriter) {
                    $binarywriter.Close()
                    $binarywriter.Dispose()
                }
            }
        }
} $SqlInstance $SqlCredential $Database $Table $Schema $FileNameColumn $BinaryColumn $Path $Query $FilePath $InputObject $EnableException $__boundQuery $__boundFileNameColumn $__boundBinaryColumn $__boundFilePath $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

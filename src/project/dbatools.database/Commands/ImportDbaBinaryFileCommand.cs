#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Imports binary files into a SQL Server table's binary column. Port of public/Import-DbaBinaryFile.ps1;
/// the workflow remains a module-scoped PowerShell compatibility hop. This is a MUTATING command with real
/// SupportsShouldProcess.
///
/// A process-only port with TWO pipeline parameters (InputObject ValueFromPipeline pos8; FilePath
/// ValueFromPipelineByPropertyName [Alias FullName] pos9). Multiple mechanisms combine:
/// (1) SHOULDPROCESS: the source declares SupportsShouldProcess (ConfirmImpact Medium) and calls
/// $Pscmdlet.ShouldProcess(...); that becomes $__realCmdlet.ShouldProcess(...) with the compiled cmdlet (this)
/// passed as $__realCmdlet, so -WhatIf/-Confirm are honored by the real cmdlet.
/// (2) CROSS-RECORD PROCESS INTERRUPT: the process opens with if (Test-FunctionInterrupt) { return } and several
/// validation guards fire Stop-Function (NO -Continue) + return, which set the interrupt. Because InputObject/FilePath
/// are pipeline params, that interrupt must persist ACROSS records: the process body is DOT-SOURCED, the module
/// interrupt variable is captured (Get-Variable -Scope 0) and emitted, and the C# field _processInterrupted (persists
/// across ProcessRecord) gates ProcessRecord. The verbatim Test-FunctionInterrupt line is inert in the fresh scope.
/// (3) CONTINUE-GUARD: two Stop-Function -Continue guards (the FilePath not-exist / is-directory checks) sit at
/// process-top with no enclosing loop, so the body is wrapped in foreach ($__continueGuard in @(1)) so their internal
/// continue is loop-bound (matching the source's "skip to next record"); the loop-bound -Continue guards inside the
/// tbl/file loops still target their own loops.
/// (4) $PSBoundParameters.FileNameColumn/.BinaryColumn are IMMUTABLE (reflect the original binding), but the body
/// REASSIGNS $FileNameColumn/$BinaryColumn (per-table), so those two references become captured originals
/// ($__psbpFileNameColumn/$__psbpBinaryColumn, snapshot at the top before any reassignment) - substituting the
/// live $FileNameColumn would diverge on the second table iteration.
/// (5) NoFileNameColumn is consumed as a VALUE (if ($NoFileNameColumn)), so it is a marshaled bool in an UNTYPED
/// inner param (binding-probed). The many Stop-Function/Write-Message get -FunctionName Import-DbaBinaryFile.
/// Surface pinned by migration/baselines/Import-DbaBinaryFile.json (positions 0-10, SupportsShouldProcess ConfirmImpact Medium).
/// </summary>
[Cmdlet(VerbsData.Import, "DbaBinaryFile", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class ImportDbaBinaryFileCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database containing the target table.</summary>
    [Parameter(Position = 2)]
    public string? Database { get; set; }

    /// <summary>The target table.</summary>
    [Parameter(Position = 3)]
    public string? Table { get; set; }

    /// <summary>The schema of the target table.</summary>
    [Parameter(Position = 4)]
    public string? Schema { get; set; }

    /// <summary>A custom INSERT statement to use.</summary>
    [Parameter(Position = 5)]
    public string? Statement { get; set; }

    /// <summary>The column that stores the file name.</summary>
    [Parameter(Position = 6)]
    public string? FileNameColumn { get; set; }

    /// <summary>The column that stores the binary file contents.</summary>
    [Parameter(Position = 7)]
    public string? BinaryColumn { get; set; }

    /// <summary>Do not store a file name column.</summary>
    [Parameter]
    public SwitchParameter NoFileNameColumn { get; set; }

    /// <summary>Table object(s) piped in from Get-DbaDbTable.</summary>
    [Parameter(ValueFromPipeline = true, Position = 8)]
    public Microsoft.SqlServer.Management.Smo.Table[]? InputObject { get; set; }

    /// <summary>The file(s) to import.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 9)]
    [Alias("FullName")]
    public System.IO.FileInfo[]? FilePath { get; set; }

    /// <summary>A directory whose files are all imported.</summary>
    [Parameter(Position = 10)]
    public System.IO.FileInfo[]? Path { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Carried across records: the process interrupt (a validation Stop-Function without -Continue stops all records).
    private bool _processInterrupted;

    // Carried across records: the source guards its whole column-detect + $Statement-build block with
    // if (-not $Statement) - a VALUE check on a NON-pipeline param, so once $Statement (and the detected
    // $FileNameColumn/$BinaryColumn) are built on the first piped table they PERSIST to every later record and the
    // block is skipped, reusing table-1's INSERT for table-2 (the source's actual behaviour). The hop re-binds
    // $Statement to the null property each ProcessRecord, so without this carry it would rebuild per-record and
    // DIVERGE (insert into the right table where the source uses the wrong one). Set once, never cleared - a value
    // that has become non-null in the source never goes back to null.
    private bool _carryAssigned;
    private string? _carryStatement;
    private string? _carryFileNameColumn;
    private string? _carryBinaryColumn;

    protected override void ProcessRecord()
    {
        // Replicates the source process block's opening if (Test-FunctionInterrupt) { return } across records.
        if (Interrupted || _processInterrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__ibfProcess"))
            {
                if (sentinel["__ibfProcess"] is Hashtable state)
                {
                    _processInterrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                    // Capture the persisted $Statement/columns so the NEXT record reproduces the source's skip.
                    if (LanguagePrimitives.IsTrue(state["CarryAssigned"]))
                    {
                        _carryAssigned = true;
                        _carryStatement = state["Statement"] as string;
                        _carryFileNameColumn = state["FileNameColumn"] as string;
                        _carryBinaryColumn = state["BinaryColumn"] as string;
                    }
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
            SqlInstance, SqlCredential, Database, Table, Schema, Statement, FileNameColumn, BinaryColumn,
            NoFileNameColumn.ToBool(), InputObject, FilePath, Path, EnableException.ToBool(),
            this, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"),
            _carryAssigned, _carryStatement, _carryFileNameColumn, _carryBinaryColumn);
    }
    // PS: the process block VERBATIM, DOT-SOURCED (cross-record interrupt) inside a continue-guard foreach (bare
    // -Continue guards). Edits: -FunctionName Import-DbaBinaryFile on the Stop-Function/Write-Message; $Pscmdlet.
    // ShouldProcess -> $__realCmdlet.ShouldProcess; $PSBoundParameters.FileNameColumn/BinaryColumn -> captured
    // originals $__psbpFileNameColumn/$__psbpBinaryColumn (snapshot before the body reassigns $FileNameColumn/$BinaryColumn).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Table, $Schema, $Statement, $FileNameColumn, $BinaryColumn, $NoFileNameColumn, $InputObject, $FilePath, $Path, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug, $__carryAssigned, $__carryStatement, $__carryFileNameColumn, $__carryBinaryColumn)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string]$Database, [string]$Table, [string]$Schema, [string]$Statement, [string]$FileNameColumn, [string]$BinaryColumn, $NoFileNameColumn, [Microsoft.SqlServer.Management.Smo.Table[]]$InputObject, [System.IO.FileInfo[]]$FilePath, [System.IO.FileInfo[]]$Path, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug, $__carryAssigned, $__carryStatement, $__carryFileNameColumn, $__carryBinaryColumn)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    $__psbpFileNameColumn = $FileNameColumn
    $__psbpBinaryColumn = $BinaryColumn
    # Cross-record carry: restore the persisted $Statement + detected columns from the previous record
    # BEFORE the build blocks (and AFTER the boundness snapshot above, so $__psbp* still reflects the caller's
    # ORIGINAL binding, not the carried value). This makes if (-not $Statement) skip on record 2+, reusing
    # table-1's INSERT + columns exactly as the source's persisted param does.
    if ($__carryAssigned) {
        $Statement = $__carryStatement
        $FileNameColumn = $__carryFileNameColumn
        $BinaryColumn = $__carryBinaryColumn
    }
    . {
        foreach ($__continueGuard in @(1)) {
        # can't be in begin because it's piped in
        if ((-not $Database -or -not $Table) -and -not $InputObject) {
            Stop-Function -Message "You must specify either Database and Table or pipe in a table" -FunctionName Import-DbaBinaryFile
            return
        }

        if ($Path -and $FilePath) {
            Stop-Function -Message "You cannot specify both -Path and -FilePath" -FunctionName Import-DbaBinaryFile
            return
        }
        if (-not $Path -and -not $FilePath) {
            Stop-Function -Message "You cannot specify either -Path or -FilePath" -FunctionName Import-DbaBinaryFile
            return
        }
        if ($Path) {
            if (-not (Test-Path -Path $Path -PathType Container)) {
                Stop-Function -Message "Path $Path does not exist" -FunctionName Import-DbaBinaryFile
                return
            }
        }

        if ($FilePath) {
            if (-not (Test-Path $FilePath)) {
                Stop-Function -Message "File $FilePath does not exist" -FunctionName Import-DbaBinaryFile -Continue
            }

            if ((Get-Item -Path $FilePath).PSIsContainer) {
                Stop-Function -Message "FilePath must be one or more files, not a directory. For directories, use Path" -FunctionName Import-DbaBinaryFile -Continue
            }
        }

        if ($Path) {
            $FilePath = Get-ChildItem -Path $Path -Recurse -File
        }

        if (Test-FunctionInterrupt) { return }
        if (-not $InputObject) {
            try {
                $InputObject = Get-DbaDbTable -SqlInstance $SqlInstance -Database $Database -Table $Table -Schema $Schema -SqlCredential $SqlCredential -EnableException
            } catch {
                Stop-Function -Message "Failed to get tables" -ErrorRecord $PSItem -FunctionName Import-DbaBinaryFile
                return
            }
        }
        Write-Message -Level Verbose -Message "Found $($InputObject.count) tables" -FunctionName Import-DbaBinaryFile -ModuleName "dbatools"
        foreach ($tbl in $InputObject) {
            # auto detect column that is binary
            # if none or multiple, make them specify the binary column
            # auto detect column that is a name
            # if none or multiple, make them specify the filename column or extension
            $server = $tbl.Parent.Parent
            $db = $tbl.Parent

            if (-not $Statement) {
                if (-not $__psbpFileNameColumn -and -not $NoFileNameColumn) {
                    $FileNameColumn = ($tbl.Columns | Where-Object Name -match Name).Name
                    if ($FileNameColumn.Count -gt 1) {
                        Stop-Function -Message "Multiple column names match the phrase 'name' in $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name). Please specify the column to use with -FileNameColumn" -FunctionName Import-DbaBinaryFile -Continue
                    }
                    if ($FileNameColumn.Count -eq 0) {
                        Stop-Function -Message "No column names match the phrase 'name' in $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name). Please specify the column to use with -FileNameColumn" -FunctionName Import-DbaBinaryFile -Continue
                    }
                }

                if (-not $__psbpBinaryColumn) {
                    $BinaryColumn = ($tbl.Columns | Where-Object { $PSItem.DataType.Name -match "binary" -or $PSItem.DataType.Name -eq "image" }).Name
                    if ($BinaryColumn.Count -gt 1) {
                        Stop-Function -Message "Multiple columns have a binary datatype in $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name). Please specify the column to use with -BinaryColumn" -FunctionName Import-DbaBinaryFile -Continue
                    }
                    if ($BinaryColumn.Count -eq 0) {
                        Stop-Function -Message "No columns have a binary datatype in $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name). Please specify the column to use with -BinaryColumn" -FunctionName Import-DbaBinaryFile -Continue
                    }
                }
            }

            foreach ($file in $FilePath) {
                $file = $file.FullName
                $filename = Split-Path -Path $file -Leaf
                if ($__realCmdlet.ShouldProcess($env:computername, "Importing $file to $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name)")) {
                    try {
                        $filestream = New-Object System.IO.FileStream $file, Open
                        Write-Message -Level Verbose -Message "Importing $filename" -FunctionName Import-DbaBinaryFile -ModuleName "dbatools"

                        $binaryreader = New-Object System.IO.BinaryReader $filestream
                        $fileBytes = $binaryreader.ReadBytes($filestream.Length)

                        if (-not $Statement) {
                            if ($NoFileNameColumn) {
                                $Statement = "INSERT INTO $db.$tbl ([$BinaryColumn]) VALUES (@FileContents)"
                            } else {
                                $Statement = "INSERT INTO $db.$tbl ([$FileNameColumn], [$BinaryColumn]) VALUES (@FileName, @FileContents)"
                            }
                        }

                        Write-Message -Level Verbose -Message "Statement: $Statement" -FunctionName Import-DbaBinaryFile -ModuleName "dbatools"
                        $cmd = $server.ConnectionContext.SqlConnectionObject.CreateCommand()
                        $cmd.CommandText = $Statement
                        $cmd.Connection.Open()

                        $datatype = ($tbl.Columns | Where-Object Name -eq $BinaryColumn).DataType
                        Write-Message -Level Verbose -Message "Binary column datatype is $datatype" -FunctionName Import-DbaBinaryFile -ModuleName "dbatools"
                        if (-not $NoFileNameColumn) {
                            $null = $cmd.Parameters.AddWithValue("@FileName", $filename)
                        }
                        $null = $cmd.Parameters.AddWithValue("@FileContents", $datatype).Value = $fileBytes
                        $null = $cmd.ExecuteScalar()

                        try {
                            $cmd.Connection.Close()
                            $cmd.Dispose()
                            $filestream.Close()
                            $filestream.Dispose()
                            $binaryreader.Close()
                            $binaryreader.Dispose()
                        } catch {
                            Write-Message -Level Verbose -Message "Something went wrong: $PSItem" -FunctionName Import-DbaBinaryFile -ModuleName "dbatools"
                        }

                        [PSCustomObject]@{
                            ComputerName = $tbl.ComputerName
                            InstanceName = $tbl.InstanceName
                            SqlInstance  = $tbl.SqlInstance
                            Database     = $db.Name
                            Table        = $tbl.Name
                            FilePath     = $file
                            Status       = "Success"
                        }
                    } catch {
                        Stop-Function -Message "Failed to import $file" -ErrorRecord $PSItem -FunctionName Import-DbaBinaryFile -Continue
                    } finally {
                        if ($filestream.CanRead) {
                            $filestream.Close()
                            $filestream.Dispose()
                        }
                        if ($binaryreader) {
                            $binaryreader.Close()
                            $binaryreader.Dispose()
                        }
                        $null = $server | Disconnect-DbaInstance
                    }
                }
            }
        }
        }
    }
    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    # Emit the persisted $Statement/columns so the next record reproduces the source's if(-not $Statement) skip.
    # CarryAssigned tracks "$Statement has become non-null" - once true the source never rebuilds it, so we forward it.
    @{ __ibfProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value); CarryAssigned = [bool]$Statement; Statement = $Statement; FileNameColumn = $FileNameColumn; BinaryColumn = $BinaryColumn } }
} $SqlInstance $SqlCredential $Database $Table $Schema $Statement $FileNameColumn $BinaryColumn $NoFileNameColumn $InputObject $FilePath $Path $EnableException $__realCmdlet $__boundVerbose $__boundDebug $__carryAssigned $__carryStatement $__carryFileNameColumn $__carryBinaryColumn @__commonParameters 3>&1 2>&1
""";
}

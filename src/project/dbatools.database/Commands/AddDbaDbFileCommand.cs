#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Adds data files to existing filegroups in SQL Server databases. Port of
/// public/Add-DbaDbFile.ps1; the workflow remains a module-scoped PowerShell compatibility
/// hop.
///
/// The WHOLE process body rides ONE verbatim hop per pipeline record. The body never calls
/// Connect-DbaInstance - it reaches the server through Get-DbaDatabase and reads $db.Parent -
/// so there is no per-instance connect to lift into C# and no NestedConnect.
///
/// Every record is self-contained, so there is no process-complete sentinel and no C# state
/// field. $InputObject is rebound by the engine on each record, so its "+=" accumulation
/// cannot leak across records. $FileName and $Path are parameters the body reassigns, but
/// each reassignment is guarded by a Test-Bound check that reads $PSBoundParameters - which
/// an assignment never mutates - so the guard stays true and the value is re-derived on every
/// database iteration before any read. The retired function's surviving values were therefore
/// dead, and a fresh value per record matches it.
///
/// Test-Bound cannot ride the hop (it scope-walks the caller's $PSBoundParameters, which
/// inside the hop is the inner scriptblock's own positional binding, where every parameter
/// always appears bound). All five call sites are flag-substituted with carried bound flags.
/// $Pscmdlet.ShouldProcess routes to the real cmdlet via $__realCmdlet so -WhatIf and any
/// yes-to-all answer persist across records. In-hop Stop-Function and Write-Message carry
/// -FunctionName because Stop-Function defaults it from Get-PSCallStack, and the hop's stack
/// frame is generated script; -ModuleName/-File/-Line still misattribute [DEF-006].
/// $EnableException rides the hop param scope because Stop-Function self-defaults it with a
/// scope-walking $EnableException = $EnableException default.
///
/// Surface pinned by migration/baselines/Add-DbaDbFile.json.
/// </summary>
[Cmdlet(VerbsCommon.Add, "DbaDbFile", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class AddDbaDbFileCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) containing the filegroup where the file will be added.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>The name of the existing filegroup the new file is added to.</summary>
    [Parameter(Position = 3)]
    public string? FileGroup { get; set; }

    /// <summary>The logical name for the new file; auto-generated when omitted.</summary>
    [Parameter(Position = 4)]
    public string? FileName { get; set; }

    /// <summary>The full physical path for the new file; the instance default data
    /// directory is used when omitted.</summary>
    [Parameter(Position = 5)]
    public string? Path { get; set; }

    /// <summary>The initial size of the file in megabytes.</summary>
    [Parameter(Position = 6)]
    [PsIntCast]
    public int Size { get; set; } = 128;

    /// <summary>The file growth increment in megabytes.</summary>
    [Parameter(Position = 7)]
    [PsIntCast]
    public int Growth { get; set; } = 64;

    /// <summary>The maximum size the file can grow to in megabytes; -1 is unlimited.</summary>
    [Parameter(Position = 8)]
    [PsIntCast]
    public int MaxSize { get; set; } = -1;

    /// <summary>Database object(s), typically from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 9)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
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
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, FileGroup, FileName, Path,
            Size, Growth, MaxSize, InputObject, EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(Database)), TestBound(nameof(FileGroup)),
            TestBound(nameof(FileName)), TestBound(nameof(Path)),
            this, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the ENTIRE process body VERBATIM per record. Substitutions only: $Pscmdlet ->
    // $__realCmdlet, the five Test-Bound reads -> carried bound flags, and explicit
    // -FunctionName Add-DbaDbFile on every Stop-Function/Write-Message. The filegroup and
    // duplicate-name guards, the memory-optimized branch and its version check, the
    // auto-generated logical name and default path, the SMO DataFile construction with its
    // KB conversions, and every comment ride as-is.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $FileGroup, $FileName, $Path, $Size, $Growth, $MaxSize, $InputObject, $EnableException, $__boundSqlInstance, $__boundDatabase, $__boundFileGroup, $__boundFileName, $__boundPath, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string]$FileGroup, [string]$FileName, [string]$Path, [int]$Size, [int]$Growth, [int]$MaxSize, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundDatabase, $__boundFileGroup, $__boundFileName, $__boundPath, $__realCmdlet, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if (-not $__boundFileGroup) {
            Stop-Function -Message "FileGroup is required" -FunctionName Add-DbaDbFile
            return
        }

        if (($__boundSqlInstance) -and (-not $__boundDatabase)) {
            Stop-Function -Message "Database is required when SqlInstance is specified" -FunctionName Add-DbaDbFile
            return
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            # Verify the filegroup exists
            if ($db.FileGroups.Name -notcontains $FileGroup) {
                Stop-Function -Message "Filegroup $FileGroup does not exist in database $($db.Name) on $($server.Name)" -Continue -FunctionName Add-DbaDbFile
            }

            $fileGroupObject = $db.FileGroups[$FileGroup]

            # Check SQL Server version for memory-optimized filegroups
            if ($fileGroupObject.FileGroupType -eq "MemoryOptimizedDataFileGroup") {
                if ($server.VersionMajor -lt 12) {
                    Stop-Function -Message "Memory-optimized filegroups require SQL Server 2014 or higher. Server $($server.Name) is version $($server.VersionMajor) (SQL Server $($server.VersionString))." -Continue -FunctionName Add-DbaDbFile
                }
            }

            # Auto-generate filename if not provided
            if (-not $__boundFileName) {
                $existingFileCount = $fileGroupObject.Files.Count
                $FileName = "$($db.Name)_$($FileGroup)_$($existingFileCount + 1)"
            }

            # Check if a file with this logical name already exists
            if ($db.FileGroups.Files.Name -contains $FileName) {
                Stop-Function -Message "A file with the logical name $FileName already exists in database $($db.Name) on $($server.Name)" -Continue -FunctionName Add-DbaDbFile
            }

            # Determine the file path
            if (-not $__boundPath) {
                $defaultPath = (Get-DbaDefaultPath -SqlInstance $server).Data

                # For MemoryOptimizedDataFileGroup, use directory path without file extension
                if ($fileGroupObject.FileGroupType -eq "MemoryOptimizedDataFileGroup") {
                    $Path = "$defaultPath\$FileName"
                } else {
                    # Standard data file with .ndf extension
                    $Path = "$defaultPath\$FileName.ndf"
                }
            }

            if ($__realCmdlet.ShouldProcess($server.Name, "Adding file $FileName to filegroup $FileGroup in database $($db.Name) on $($server.Name)")) {
                try {
                    # For MemoryOptimizedDataFileGroup, we create a different type of file
                    if ($fileGroupObject.FileGroupType -eq "MemoryOptimizedDataFileGroup") {
                        Write-Message -Level Verbose -Message "Creating memory-optimized container $FileName in filegroup $FileGroup" -FunctionName Add-DbaDbFile -ModuleName "dbatools"

                        $newFile = New-Object Microsoft.SqlServer.Management.Smo.DataFile -ArgumentList $fileGroupObject, $FileName
                        $newFile.FileName = $Path

                        # Memory-optimized filegroups don't use Size, Growth, or MaxSize properties
                        # Add the file to the filegroup
                        $fileGroupObject.Files.Add($newFile)

                        # Alter the filegroup to persist the changes
                        $fileGroupObject.Alter()

                        # Refresh to get updated state
                        $db.Refresh()

                        # Return the newly created file
                        $db.FileGroups[$FileGroup].Files[$FileName]
                    } else {
                        # Standard data file creation
                        Write-Message -Level Verbose -Message "Creating data file $FileName in filegroup $FileGroup" -FunctionName Add-DbaDbFile -ModuleName "dbatools"

                        $newFile = New-Object Microsoft.SqlServer.Management.Smo.DataFile -ArgumentList $fileGroupObject, $FileName
                        $newFile.FileName = $Path
                        $newFile.Size = ($Size * 1024)
                        $newFile.Growth = ($Growth * 1024)
                        $newFile.GrowthType = "KB"

                        if ($MaxSize -gt 0) {
                            $newFile.MaxSize = ($MaxSize * 1024)
                        } else {
                            $newFile.MaxSize = -1
                        }

                        # Add the file to the filegroup
                        $fileGroupObject.Files.Add($newFile)

                        # Alter the filegroup to persist the changes
                        $fileGroupObject.Alter()

                        # Refresh to get updated state
                        $db.Refresh()

                        # Return the newly created file
                        $db.FileGroups[$FileGroup].Files[$FileName]
                    }
                } catch {
                    Stop-Function -Message "Failure on $($server.Name) to add file $FileName to filegroup $FileGroup in database $($db.Name)" -ErrorRecord $_ -Continue -FunctionName Add-DbaDbFile
                }
            }
        }
} $SqlInstance $SqlCredential $Database $FileGroup $FileName $Path $Size $Growth $MaxSize $InputObject $EnableException $__boundSqlInstance $__boundDatabase $__boundFileGroup $__boundFileName $__boundPath $__realCmdlet $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

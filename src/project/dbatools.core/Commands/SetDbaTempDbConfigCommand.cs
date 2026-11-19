#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets tempdb data/log configuration per best practices. Port of
/// public/Set-DbaTempDbConfig.ps1 (W3-099). WHOLE-RECORD verbatim hop over a NO-VFP
/// surface: SqlInstance is NOT pipeline-bound, so process runs exactly once and the row
/// is STRUCTURALLY IMMUNE to the cross-record class - every quirk lives inside the one
/// hop and rides verbatim. CLASSIFICATION TABLE (promoted question answered per mutated
/// param/local, all confined to the single foreach): $DataFileCount (set from cores on
/// iteration 1, sticks for later instances), $DataPath/$LogPath (backfilled from
/// instance 1's tempdb, stick), $LogFileSize (backfilled from the log file's SizeMb,
/// sticks), $DataFileGrowth/$LogFileGrowth (zeroed under -DisableGrowth, idempotent),
/// $invalidPathFound (branch-assigned/unconditionally-read - B's W1-124 signature -
/// STALE across instances: a bad path on instance 1 re-Stop-Functions instance 2 even
/// when its paths validate; smoke-pinned), and $sql - NEVER INITIALIZED and NEVER
/// RESET: $null += string yields ONE concatenated string that ACCUMULATES ACROSS
/// INSTANCES (instance 2 re-executes instance 1's statements; smoke-pinned). The
/// OutputScriptOnly `return` exits the whole dot-block, SKIPPING remaining instances -
/// same as the source's process-block return (smoke-pinned). Gate routes to the REAL
/// cmdlet ($Pscmdlet -> $__realCmdlet, hold-free); the two Test-Bound calls ride as
/// carried flags (W3-093 law). Checklist greps done: Connect-DbaInstance/Test-DbaPath
/// are compiled (no scope-walk/callstack exposure), Get-DbaDbFile is a scope-walk-free
/// PS function, Stop-Function's Get-PSCallStack handled by -FunctionName (W1-090).
/// Bind-time casts per the laws: [PsIntCast] on all five int params (W1-043),
/// [PsStringArrayCast] on DataPath (W1-035 conservative), [PsStringCast] on
/// LogPath/OutFile (W1-032). NO WarningAction carrier (codex W3-005 r3). Surface pinned
/// by migration/baselines/Set-DbaTempDbConfig.json (implicit positions 0-9, no sets,
/// SqlInstance Mandatory pos0 NO-VFP, DataFileSize Mandatory pos3, ConfirmImpact
/// Medium).
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaTempDbConfig", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class SetDbaTempDbConfigCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Credential for SQL Server authentication.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Number of tempdb data files (defaults to logical cores, capped at 8).</summary>
    [Parameter(Position = 2)]
    [PsIntCast]
    public int DataFileCount { get; set; }

    /// <summary>Total data file size in MB, split evenly across the data files.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [PsIntCast]
    public int DataFileSize { get; set; }

    /// <summary>Log file size in MB (defaults to the current log file size).</summary>
    [Parameter(Position = 4)]
    [PsIntCast]
    public int LogFileSize { get; set; }

    /// <summary>Data file growth in MB.</summary>
    [Parameter(Position = 5)]
    [PsIntCast]
    public int DataFileGrowth { get; set; } = 512;

    /// <summary>Log file growth in MB.</summary>
    [Parameter(Position = 6)]
    [PsIntCast]
    public int LogFileGrowth { get; set; } = 512;

    /// <summary>Directory path(s) for the tempdb data files (round-robined when multiple).</summary>
    [Parameter(Position = 7)]
    [PsStringArrayCast]
    public string[]? DataPath { get; set; }

    /// <summary>Directory path for the tempdb log file.</summary>
    [Parameter(Position = 8)]
    [PsStringCast]
    public string? LogPath { get; set; }

    /// <summary>File to write the generated T-SQL script to instead of executing it.</summary>
    [Parameter(Position = 9)]
    [PsStringCast]
    public string? OutFile { get; set; }

    /// <summary>Returns the generated T-SQL script instead of executing it.</summary>
    [Parameter]
    public SwitchParameter OutputScriptOnly { get; set; }

    /// <summary>Disables file growth on the data and log files.</summary>
    [Parameter]
    public SwitchParameter DisableGrowth { get; set; }

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
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, DataFileCount, DataFileSize, LogFileSize,
            DataFileGrowth, LogFileGrowth, DataPath, LogPath, OutFile,
            OutputScriptOnly.ToBool(), DisableGrowth.ToBool(), EnableException.ToBool(),
            TestBound(nameof(DataPath)), TestBound(nameof(LogPath)), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the ENTIRE process body VERBATIM (single hop - no VFP). Substitutions only:
    // $Pscmdlet -> $__realCmdlet on the gate, the two Test-Bound calls -> carried flags,
    // and explicit -FunctionName Set-DbaTempDbConfig on hop-frame Stop-Function/
    // Write-Message (W1-090). The uninitialized/unreset $sql accumulator, the stale
    // $invalidPathFound, the sticky backfilled params and the dot-block-exiting
    // OutputScriptOnly return all ride AS-IS.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $DataFileCount, $DataFileSize, $LogFileSize, $DataFileGrowth, $LogFileGrowth, $DataPath, $LogPath, $OutFile, $OutputScriptOnly, $DisableGrowth, $EnableException, $__boundDataPath, $__boundLogPath, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [int]$DataFileCount, [int]$DataFileSize, [int]$LogFileSize, [int]$DataFileGrowth, [int]$LogFileGrowth, [string[]]$DataPath, [string]$LogPath, [string]$OutFile, $OutputScriptOnly, $DisableGrowth, $EnableException, $__boundDataPath, $__boundLogPath, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaTempDbConfig
            }

            $cores = $server.Processors
            if ($cores -gt 8) {
                $cores = 8
            }

            #Set DataFileCount if not specified. If specified, check against best practices.
            if (-not $DataFileCount) {
                $DataFileCount = $cores
                Write-Message -Message "Data file count set to number of cores: $DataFileCount" -Level Verbose -FunctionName Set-DbaTempDbConfig -ModuleName "dbatools"
            } else {
                if ($DataFileCount -gt $cores) {
                    Write-Message -Message "Data File Count of $DataFileCount exceeds the Logical Core Count of $cores. This is outside of best practices." -Level Warning -FunctionName Set-DbaTempDbConfig -ModuleName "dbatools"
                }
                Write-Message -Message "Data file count set explicitly: $DataFileCount" -Level Verbose -FunctionName Set-DbaTempDbConfig -ModuleName "dbatools"
            }

            $DataFilesizeSingle = $([Math]::Floor($DataFileSize / $DataFileCount))
            Write-Message -Message "Single data file size (MB): $DataFilesizeSingle." -Level Verbose -FunctionName Set-DbaTempDbConfig -ModuleName "dbatools"

            if ($__boundDataPath) {
                foreach ($dataDirPath in $DataPath) {
                    if ((Test-DbaPath -SqlInstance $server -Path $dataDirPath) -eq $false) {
                        $invalidPathFound = "$dataDirPath does not exist"
                        break
                    }
                }

                if ($invalidPathFound) {
                    Stop-Function -Message $invalidPathFound -Continue -FunctionName Set-DbaTempDbConfig
                }
            } else {
                $Filepath = $server.Databases['tempdb'].Query('SELECT physical_name AS PhysicalName FROM sys.database_files WHERE file_id = 1').PhysicalName
                $DataPath = Split-Path $Filepath
            }

            Write-Message -Message "Using data path(s): $DataPath." -Level Verbose -FunctionName Set-DbaTempDbConfig -ModuleName "dbatools"

            if ($__boundLogPath) {
                if ((Test-DbaPath -SqlInstance $server -Path $LogPath) -eq $false) {
                    Stop-Function -Message "$LogPath is an invalid path." -Continue -FunctionName Set-DbaTempDbConfig
                }
            } else {
                $Filepath = $server.Databases['tempdb'].Query('SELECT physical_name AS PhysicalName FROM sys.database_files WHERE file_id = 2').PhysicalName
                $LogPath = Split-Path $Filepath
            }
            Write-Message -Message "Using log path: $LogPath." -Level Verbose -FunctionName Set-DbaTempDbConfig -ModuleName "dbatools"

            # Check if the file growth needs to be disabled
            if ($DisableGrowth) {
                $DataFileGrowth = 0
                $LogFileGrowth = 0
            }

            # Check current tempdb. Throw an error if current tempdb is larger than config.
            $CurrentFileCount = $server.Databases['tempdb'].Query('SELECT COUNT(1) AS FileCount FROM sys.database_files WHERE type=0').FileCount
            $TooBigCount = $server.Databases['tempdb'].Query("SELECT TOP 1 (size/128) AS Size FROM sys.database_files WHERE size/128 > $DataFilesizeSingle AND type = 0").Size

            if ($CurrentFileCount -gt $DataFileCount) {
                Stop-Function -Message "Current tempdb in $instance is not suitable to be reconfigured. The current tempdb has a greater number of files ($CurrentFileCount) than the calculated configuration ($DataFileCount)." -Continue -FunctionName Set-DbaTempDbConfig
            }

            if ($TooBigCount) {
                Stop-Function -Message "Current tempdb in $instance is not suitable to be reconfigured. The current tempdb has files with a size ($TooBigCount MB) larger than the calculated individual file configuration ($DataFilesizeSingle MB)." -Continue -FunctionName Set-DbaTempDbConfig
            }

            Write-Message -Message "tempdb configuration validated." -Level Verbose -FunctionName Set-DbaTempDbConfig -ModuleName "dbatools"

            $DataFiles = Get-DbaDbFile -SqlInstance $server -Database tempdb | Where-Object Type -eq 0 | Select-Object LogicalName, PhysicalName

            # Used to round-robin the placement of tempdb data files if more than one value for $DataPath was passed in.
            $dataPathIndexToUse = 0

            #Checks passed, process reconfiguration
            for ($i = 0; $i -lt $DataFileCount; $i++) {
                $File = $DataFiles[$i]

                if ($DataPath.Count -gt 1) {
                    $newDataDirPath = $DataPath[$dataPathIndexToUse]

                    $dataPathIndexToUse += 1

                    # reset the round robin index variable
                    if ($dataPathIndexToUse -ge $DataPath.Count ) {
                        $dataPathIndexToUse = 0
                    }
                } else {
                    $newDataDirPath = $DataPath
                }

                if ($File) {
                    $Filename = Split-Path $File.PhysicalName -Leaf
                    $LogicalName = $File.LogicalName
                    $NewPath = "$newDataDirPath\$Filename"
                    $sql += "ALTER DATABASE tempdb MODIFY FILE(name=$LogicalName,filename='$NewPath',size=$DataFilesizeSingle MB,filegrowth=$DataFileGrowth);"
                } else {
                    $NewName = "tempdev$i.ndf"
                    $NewPath = "$newDataDirPath\$NewName"
                    $sql += "ALTER DATABASE tempdb ADD FILE(name=tempdev$i,filename='$NewPath',size=$DataFilesizeSingle MB,filegrowth=$DataFileGrowth);"
                }
            }

            $logfile = Get-DbaDbFile -SqlInstance $server -Database tempdb | Where-Object Type -eq 1 | Select-Object LogicalName, PhysicalName, @{L = "SizeMb"; E = { $_.Size.Megabyte } }

            if ($LogPath -or $LogFileSize) {
                $Filename = Split-Path $logfile.PhysicalName -Leaf
                $LogicalName = $logfile.LogicalName

                if ($LogPath) {
                    $NewPath = "$LogPath\$Filename"
                } else {
                    $NewPath = $logfile.PhysicalName
                }

                if (-not($LogFileSize)) {
                    $LogFileSize = $logfile.SizeMb
                }

                $sql += "ALTER DATABASE tempdb MODIFY FILE(name=$LogicalName,filename='$NewPath',size=$LogFileSize MB,filegrowth=$LogFileGrowth);"
            }

            Write-Message -Message "SQL Statement to resize tempdb." -Level Verbose -FunctionName Set-DbaTempDbConfig -ModuleName "dbatools"
            Write-Message -Message ($sql -join "`n`n") -Level Verbose -FunctionName Set-DbaTempDbConfig -ModuleName "dbatools"

            if ($OutputScriptOnly) {
                return $sql
            } elseif ($OutFile) {
                $sql | Set-Content -Path $OutFile
            } else {
                if ($__realCmdlet.ShouldProcess($instance, "Executing query and informing that a restart is required.")) {
                    try {
                        $server.Databases['master'].ExecuteNonQuery($sql)
                        Write-Message -Level Verbose -Message "tempdb successfully reconfigured." -FunctionName Set-DbaTempDbConfig -ModuleName "dbatools"

                        [PSCustomObject]@{
                            ComputerName       = $server.ComputerName
                            InstanceName       = $server.ServiceName
                            SqlInstance        = $server.DomainInstanceName
                            DataFileCount      = $DataFileCount
                            DataFileSize       = [dbasize]($DataFileSize * 1024 * 1024)
                            SingleDataFileSize = [dbasize]($DataFilesizeSingle * 1024 * 1024)
                            LogSize            = [dbasize]($LogFileSize * 1024 * 1024)
                            DataPath           = $DataPath
                            LogPath            = $LogPath
                            DataFileGrowth     = [dbasize]($DataFileGrowth * 1024 * 1024)
                            LogFileGrowth      = [dbasize]($LogFileGrowth * 1024 * 1024)
                        }

                        Write-Message -Level Output -Message "tempdb reconfigured. You must restart the SQL Service for settings to take effect." -FunctionName Set-DbaTempDbConfig -ModuleName "dbatools"
                    } catch {
                        Stop-Function -Message "Unable to reconfigure tempdb. Exception: $_" -Target $sql -ErrorRecord $_ -Continue -FunctionName Set-DbaTempDbConfig
                    }
                }
            }
        }
    }
} $SqlInstance $SqlCredential $DataFileCount $DataFileSize $LogFileSize $DataFileGrowth $LogFileGrowth $DataPath $LogPath $OutFile $OutputScriptOnly $DisableGrowth $EnableException $__boundDataPath $__boundLogPath $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

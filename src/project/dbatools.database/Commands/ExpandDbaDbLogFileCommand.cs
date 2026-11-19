#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Grows a transaction log file to a target size in controlled increments to minimize VLF
/// fragmentation. Port of public/Expand-DbaDbLogFile.ps1; the workflow remains a module-scoped
/// PowerShell compatibility hop.
///
/// No parameter is ValueFromPipeline, so process fires exactly once; the source's begin, process and
/// end blocks share one function scope, so they are CONCATENATED into one hop rather than split into
/// begin/process hops - which keeps in one scope the two nested helper functions the begin block
/// defines and the process block calls (Get-VlfCountForGrowthPlan, Find-TargetVlfIncrementSize), the
/// MB-to-KB state, $ErrorActionPreference = "Inquire", and the $server connection. The process body
/// is DOT-SOURCED (. { }) because PowerShell runs the end block even when process returns early (its
/// Test-FunctionInterrupt guard and deeper returns), so the end block's final message must survive
/// process's returns; begin has no early return and is not dot-sourced. No pipeline means no
/// cross-record state and no sentinel.
///
/// Edits to the copied body: $Pscmdlet/$PSCmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess (four
/// gates), and -FunctionName Expand-DbaDbLogFile on every direct Stop-Function/Write-Message (the two
/// nested helpers contain none). Surface pinned by migration/baselines/Expand-DbaDbLogFile.json (two
/// parameter sets Default/Shrink, explicit positions, no ValueFromPipeline).
/// </summary>
[Cmdlet(VerbsData.Expand, "DbaDbLogFile", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium, DefaultParameterSetName = "Default")]
public sealed class ExpandDbaDbLogFileCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance.</summary>
    [Parameter(Position = 1, Mandatory = true)]
    public DbaInstanceParameter SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instance.</summary>
    [Parameter(Position = 3)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 4)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>The target log-file size in megabytes.</summary>
    [Parameter(Position = 5, Mandatory = true)]
    [PsIntCast]
    public int TargetLogSize { get; set; }

    /// <summary>The growth increment in megabytes.</summary>
    [Parameter(Position = 6)]
    [PsIntCast]
    public int IncrementSize { get; set; } = -1;

    /// <summary>The desired maximum VLF count.</summary>
    [Parameter]
    [PsIntCast]
    public int TargetVlfCount { get; set; } = -1;

    /// <summary>The log file id to grow.</summary>
    [Parameter(Position = 7)]
    [PsIntCast]
    public int LogFileId { get; set; } = -1;

    /// <summary>Shrink the log file before expanding.</summary>
    [Parameter(Position = 8, Mandatory = true, ParameterSetName = "Shrink")]
    public SwitchParameter ShrinkLogFile { get; set; }

    /// <summary>The size to shrink to, in megabytes.</summary>
    [Parameter(Position = 9, Mandatory = true, ParameterSetName = "Shrink")]
    [PsIntCast]
    public int ShrinkSize { get; set; }

    /// <summary>The backup directory for the pre-shrink log backup.</summary>
    [Parameter(Position = 10, ParameterSetName = "Shrink")]
    [AllowEmptyString]
    [PsStringCast]
    public string? BackupDirectory { get; set; }

    /// <summary>Skip the disk-space validation.</summary>
    [Parameter]
    public SwitchParameter ExcludeDiskSpaceValidation { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // Streaming, not buffered (DEF-001): the command mutates log files database-by-database and
        // emits one result per database; buffered InvokeScoped discarded the results of databases
        // already grown when a later database's failure terminated the hop under -EnableException.
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
            SqlInstance, SqlCredential, Database, ExcludeDatabase, TargetLogSize, IncrementSize,
            TargetVlfCount, LogFileId, ShrinkLogFile.ToBool(), ShrinkSize, BackupDirectory,
            ExcludeDiskSpaceValidation.ToBool(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin + process + end blocks CONCATENATED and run once (no pipeline). Edits:
    // $Pscmdlet/$PSCmdlet.ShouldProcess -> $__realCmdlet, and -FunctionName on direct
    // Stop-Function/Write-Message. The process body is dot-sourced so the end block survives its
    // early returns. The two nested helper functions ride verbatim in the begin section.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $TargetLogSize, $IncrementSize, $TargetVlfCount, $LogFileId, $ShrinkLogFile, $ShrinkSize, $BackupDirectory, $ExcludeDiskSpaceValidation, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, [int]$TargetLogSize, [int]$IncrementSize, [int]$TargetVlfCount, [int]$LogFileId, $ShrinkLogFile, [int]$ShrinkSize, [string]$BackupDirectory, $ExcludeDiskSpaceValidation, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        Write-Message -Level Verbose -Message "Set ErrorActionPreference to Inquire." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
        $ErrorActionPreference = 'Inquire'

        #Convert MB to KB (SMO works in KB)
        Write-Message -Level Verbose -Message "Convert variables MB to KB (SMO works in KB)." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
        [int]$TargetLogSizeKB = $TargetLogSize * 1024
        [int]$LogIncrementSize = $IncrementSize * 1024
        [int]$ShrinkSizeKB = $ShrinkSize * 1024
        [int]$SuggestLogIncrementSize = 0
        [bool]$LogByFileID = if ($LogFileId -eq -1) {
            $false
        } else {
            $true
        }

        function Get-VlfCountForGrowthPlan {
            param (
                [long]$InitialSizeKB,
                [long]$TargetSizeKB,
                [long]$IncrementKB,
                [int]$SqlMajorVersion
            )

            [int]$estimatedVlfCount = 0
            [long]$simulatedSizeKB = $InitialSizeKB

            while ($simulatedSizeKB -lt $TargetSizeKB) {
                [long]$growthSizeKB = $TargetSizeKB - $simulatedSizeKB

                if ($growthSizeKB -gt $IncrementKB) {
                    $growthSizeKB = $IncrementKB
                }

                if ($SqlMajorVersion -ge 12 -and $growthSizeKB -lt ($simulatedSizeKB / 8)) {
                    $estimatedVlfCount += 1
                } elseif ($growthSizeKB -lt (64 * 1024)) {
                    $estimatedVlfCount += 4
                } elseif ($growthSizeKB -lt (1024 * 1024)) {
                    $estimatedVlfCount += 8
                } else {
                    $estimatedVlfCount += 16
                }

                $simulatedSizeKB += $growthSizeKB
            }

            return $estimatedVlfCount
        }

        function Find-TargetVlfIncrementSize {
            param (
                [long]$CurrentSizeKB,
                [long]$TargetSizeKB,
                [int]$AdditionalVlfsAllowed,
                [int]$SqlMajorVersion
            )

            if ($TargetSizeKB -le $CurrentSizeKB -or $AdditionalVlfsAllowed -lt 1) {
                return $null
            }

            [long]$totalGrowthKB = $TargetSizeKB - $CurrentSizeKB
            [long]$minIncrementKB = 1024
            [long]$fourVlfMinimumKB = $minIncrementKB
            $searchRanges = @()

            if ($SqlMajorVersion -ge 12) {
                [long]$maxOneVlfIncrementKB = [Math]::Floor(($CurrentSizeKB - 1) / 8)

                if ($maxOneVlfIncrementKB -ge $minIncrementKB) {
                    $searchRanges += @{
                        Minimum = $minIncrementKB
                        Maximum = [Math]::Min($totalGrowthKB, $maxOneVlfIncrementKB)
                    }
                }

                $fourVlfMinimumKB = [Math]::Max($minIncrementKB, $maxOneVlfIncrementKB + 1)
            }

            if ($fourVlfMinimumKB -lt (64 * 1024)) {
                $searchRanges += @{
                    Minimum = $fourVlfMinimumKB
                    Maximum = [Math]::Min($totalGrowthKB, (64 * 1024) - 1)
                }
            }

            if ($totalGrowthKB -ge (64 * 1024)) {
                $searchRanges += @{
                    Minimum = 64 * 1024
                    Maximum = [Math]::Min($totalGrowthKB, (1024 * 1024) - 1)
                }
            }

            if ($totalGrowthKB -ge (1024 * 1024)) {
                $searchRanges += @{
                    Minimum = 1024 * 1024
                    Maximum = $totalGrowthKB
                }
            }

            foreach ($searchRange in $searchRanges) {
                [long]$rangeMinimumKB = $searchRange.Minimum
                [long]$rangeMaximumKB = $searchRange.Maximum
                [long]$bestIncrementKB = 0

                if ($rangeMaximumKB -lt $rangeMinimumKB) {
                    continue
                }

                while ($rangeMinimumKB -le $rangeMaximumKB) {
                    [long]$candidateIncrementKB = [Math]::Floor(($rangeMinimumKB + $rangeMaximumKB) / 2)
                    $estimatedVlfCount = Get-VlfCountForGrowthPlan -InitialSizeKB $CurrentSizeKB -TargetSizeKB $TargetSizeKB -IncrementKB $candidateIncrementKB -SqlMajorVersion $SqlMajorVersion

                    if ($estimatedVlfCount -le $AdditionalVlfsAllowed) {
                        $bestIncrementKB = $candidateIncrementKB
                        $rangeMaximumKB = $candidateIncrementKB - 1
                    } else {
                        $rangeMinimumKB = $candidateIncrementKB + 1
                    }
                }

                if ($bestIncrementKB -gt 0) {
                    return $bestIncrementKB
                }
            }

            return $null
        }

        #Set base information
        Write-Message -Level Verbose -Message "Initialize the instance '$SqlInstance'." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"

        try {
            $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -FunctionName Expand-DbaDbLogFile
        }

        if ($ShrinkLogFile -eq $true) {
            if ($BackupDirectory.length -eq 0) {
                $backupdirectory = $server.Settings.BackupDirectory
            }

            $pathexists = Test-DbaPath -SqlInstance $server -Path $backupdirectory

            if ($pathexists -eq $false) {
                Stop-Function -Message "Backup directory does not exist." -FunctionName Expand-DbaDbLogFile
            }
        }

    . {
        if (Test-FunctionInterrupt) { return }

        try {

            [datetime]$initialTime = Get-Date

            #control the iteration number
            $databaseProgressbar = 0;

            Write-Message -Level Verbose -Message "Resolving FullComputerName name." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
            # We don't have windows credentials here, so Resolve-DbaNetworkName has to respect that and work like Resolve-NetBiosName did before.
            $resolvedComputerName = Resolve-DbaComputerName -ComputerName $SqlInstance

            $databases = $server.Databases | Where-Object IsAccessible
            Write-Message -Level Verbose -Message "Number of databases found: $($databases.Count)." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }

            #go through all databases
            Write-Message -Level Verbose -Message "Processing...foreach database..." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
            foreach ($db in $databases) {
                $dbName = $db.Name

                Write-Message -Level Verbose -Message "Working on $dbName." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                $databaseProgressbar += 1

                #set step to reutilize on logging operations
                [string]$step = "$databaseProgressbar/$($Databases.Count)"

                if ($db) {
                    Write-Progress `
                        -Id 1 `
                        -Activity "Using database: $dbName on Instance: '$SqlInstance'" `
                        -PercentComplete ($databaseProgressbar / $Databases.Count * 100) `
                        -Status "Processing - $databaseProgressbar of $($Databases.Count)"

                    #Validate which file will grow
                    if ($LogByFileID) {
                        $logfile = $db.LogFiles.ItemById($LogFileId)
                    } else {
                        $logfile = $db.LogFiles[0]
                    }

                    $numLogfiles = $db.LogFiles.Count

                    Write-Message -Level Verbose -Message "$step - Use log file: $logfile." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                    $currentSize = $logfile.Size
                    $currentSizeMB = $currentSize / 1024

                    #Get the number of VLFs
                    $initialVLFCount = Measure-DbaDbVirtualLogFile -SqlInstance $server -Database $dbName

                    Write-Message -Level Verbose -Message "$step - Log file current size: $([System.Math]::Round($($currentSize/1024.0), 2)) MB " -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                    [long]$requiredSpace = ($TargetLogSizeKB - $currentSize)

                    if ($ExcludeDiskSpaceValidation -eq $false) {
                        Write-Message -Level Verbose -Message "Verifying if sufficient space exists ($([System.Math]::Round($($requiredSpace / 1024.0), 2))MB) on the volume to perform this task." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"

                        [long]$TotalTLogFreeDiskSpaceKB = 0
                        Write-Message -Level Verbose -Message "Get TLog drive free space" -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"

                        try {
                            # That would need a Credential, but we don't have one...
                            [object]$AllDrivesFreeDiskSpace = Get-DbaDiskSpace -ComputerName $resolvedComputerName | Select-Object Name, SizeInKB

                            #Verify path using Split-Path on $logfile.FileName in backwards. This way we will catch the LUNs. Example: "K:\Log01" as LUN name. Need to add final backslash if not there
                            $DrivePath = Split-Path $logfile.FileName -parent
                            $DrivePath = if (!($DrivePath.EndsWith("\"))) { "$DrivePath\" }
                            else { $DrivePath }
                            Do {
                                if ($AllDrivesFreeDiskSpace | Where-Object { $DrivePath -eq "$($_.Name)" }) {
                                    $TotalTLogFreeDiskSpaceKB = ($AllDrivesFreeDiskSpace | Where-Object { $DrivePath -eq $_.Name }).SizeInKB
                                    $match = $true
                                    break
                                } else {
                                    $match = $false
                                    $DrivePath = Split-Path $DrivePath -parent
                                    $DrivePath = if (!($DrivePath.EndsWith("\"))) { "$DrivePath\" }
                                    else { $DrivePath }
                                }

                            }
                            while (!$match -and (-not [string]::IsNullOrEmpty($DrivePath)) -and ($DrivePath -ne "\"))

                            Write-Message -Level Verbose -Message "Total TLog Free Disk Space in MB: $([System.Math]::Round($($TotalTLogFreeDiskSpaceKB / 1024.0), 2))" -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"

                        } catch {
                            #Could not validate the disk space. Will ask if we want to continue.
                            $TotalTLogFreeDiskSpaceKB = 0
                        }

                        if (($TotalTLogFreeDiskSpaceKB -le 0) -or ([string]::IsNullOrEmpty($TotalTLogFreeDiskSpaceKB))) {
                            $message = "Cannot validate freespace on drive where the log file resides for database '$dbName'. Continuing without disk space validation."
                            if (-not $__realCmdlet.ShouldProcess($server.name, $message)) {
                                Write-Message -Level Warning -Message "Operation cancelled by user" -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                                return
                            }
                            Write-Message -Level Warning -Message $message -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                        } elseif ($requiredSpace -gt $TotalTLogFreeDiskSpaceKB) {
                            Write-Message -Level Verbose -Message "There is not enough space on volume to perform this task. `r`n" `
                                "Available space: $([System.Math]::Round($($TotalTLogFreeDiskSpaceKB / 1024.0), 2))MB;`r`n" `
                                "Required space: $([System.Math]::Round($($requiredSpace / 1024.0), 2))MB;" -FunctionName Expand-DbaDbLogFile
                            return
                        }
                    }

                    if ($currentSize -ige $TargetLogSizeKB -and ($ShrinkLogFile -eq $false)) {
                        Write-Message -Level Verbose -Message "$step - [INFO] The T-Log file '$logfile' size is already equal or greater than target size - No action required." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                    } else {
                        Write-Message -Level Verbose -Message "$step - [OK] There is sufficient free space to perform this task." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"

                        # If SQL Server version is greater or equal to 2012
                        if ($server.Version.Major -ge "11") {
                            switch ($TargetLogSize) {
                                { $_ -le 64 } { $SuggestLogIncrementSize = 64 }
                                { $_ -ge 64 -and $_ -lt 256 } { $SuggestLogIncrementSize = 256 }
                                { $_ -ge 256 -and $_ -lt 1024 } { $SuggestLogIncrementSize = 512 }
                                { $_ -ge 1024 -and $_ -lt 4096 } { $SuggestLogIncrementSize = 1024 }
                                { $_ -ge 4096 -and $_ -lt 8192 } { $SuggestLogIncrementSize = 2048 }
                                { $_ -ge 8192 -and $_ -lt 16384 } { $SuggestLogIncrementSize = 4096 }
                                { $_ -ge 16384 } { $SuggestLogIncrementSize = 8192 }
                            }
                        }
                        # 2008 R2 or under
                        else {
                            switch ($TargetLogSize) {
                                { $_ -le 64 } { $SuggestLogIncrementSize = 64 }
                                { $_ -ge 64 -and $_ -lt 256 } { $SuggestLogIncrementSize = 256 }
                                { $_ -ge 256 -and $_ -lt 1024 } { $SuggestLogIncrementSize = 512 }
                                { $_ -ge 1024 -and $_ -lt 4096 } { $SuggestLogIncrementSize = 1024 }
                                { $_ -ge 4096 -and $_ -lt 8192 } { $SuggestLogIncrementSize = 2048 }
                                { $_ -ge 8192 -and $_ -lt 16384 } { $SuggestLogIncrementSize = 4000 }
                                { $_ -ge 16384 } { $SuggestLogIncrementSize = 8000 }
                            }

                            if (($IncrementSize % 4096) -eq 0) {
                                Write-Message -Level Verbose -Message "Your instance version is below SQL 2012, remember the known BUG mentioned on HELP. `r`nUse Get-Help Expand-DbaTLogFileResponsibly to read help`r`nUse a different value for incremental size.`r`n" -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                                return
                            }
                        }
                        Write-Message -Level Verbose -Message "Instance $server version: $($server.Version.Major) - Suggested TLog increment size: $($SuggestLogIncrementSize)MB" -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"

                        # Shrink Log File to desired size before re-growth to desired size (You need to remove as many VLF's as possible to ensure proper growth)
                        $ShrinkSize = $ShrinkSizeKB / 1024
                        if ($ShrinkLogFile -eq $true) {
                            if ($db.RecoveryModel -eq [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Simple) {
                                Write-Message -Level Warning -Message "Database '$dbName' is in Simple RecoveryModel which does not allow log backups. Do not specify -ShrinkLogFile and -ShrinkSize parameters." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                                Continue
                            }

                            try {
                                $sql = "SELECT last_log_backup_lsn FROM sys.database_recovery_status WHERE database_id = DB_ID('$dbName')"
                                $sqlResult = $server.ConnectionContext.ExecuteWithResults($sql);

                                if ($sqlResult.Tables[0].Rows[0]["last_log_backup_lsn"] -is [System.DBNull]) {
                                    Write-Message -Level Warning -Message "First, you need to make a full backup before you can do Tlog backup on database '$dbName' (last_log_backup_lsn is null)." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                                    Continue
                                }
                            } catch {
                                Stop-Function -Message "Can't execute SQL on $server. `r`n $($_)" -Continue -FunctionName Expand-DbaDbLogFile
                            }

                            If ($__realCmdlet.ShouldProcess($($server.name), "Backing up TLog for $dbName")) {
                                Write-Message -Level Verbose -Message "We are about to backup the Tlog for database '$dbName' to '$backupdirectory' and shrink the log." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                                Write-Message -Level Verbose -Message "Starting Size = $currentSizeMB." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"

                                $DefaultCompression = $server.Configuration.DefaultBackupCompression.ConfigValue

                                if ($currentSizeMB -gt $ShrinkSize) {
                                    $backupRetries = 1
                                    Do {
                                        try {
                                            $percent = $null
                                            $backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
                                            $backup.Action = [Microsoft.SqlServer.Management.Smo.BackupActionType]::Log
                                            $backup.BackupSetDescription = "Transaction Log backup of " + $dbName
                                            $backup.BackupSetName = $dbName + " Backup"
                                            $backup.Database = $dbName
                                            $backup.MediaDescription = "Disk"
                                            $dt = Get-Date -format yyyyMMddHHmmssms
                                            $null = $backup.Devices.AddDevice($backupdirectory + "\" + $dbName + "_db_" + $dt + ".trn", 'File')
                                            if ($DefaultCompression -eq $true) {
                                                $backup.CompressionOption = 1
                                            } else {
                                                $backup.CompressionOption = 0
                                            }
                                            $null = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
                                                Write-Progress -id 2 -ParentId 1 -activity "Backing up $dbName to $server" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
                                            }
                                            $backup.add_PercentComplete($percent)
                                            $backup.PercentCompleteNotification = 10
                                            $backup.add_Complete($complete)
                                            Write-Progress -id 2 -ParentId 1 -activity "Backing up $dbName to $server" -percentcomplete 0 -Status ([System.String]::Format("Progress: {0} %", 0))
                                            $backup.SqlBackup($server)
                                            Write-Progress -id 2 -ParentId 1 -activity "Backing up $dbName to $server" -status "Complete" -Completed
                                            $logfile.Shrink($ShrinkSize, [Microsoft.SqlServer.Management.SMO.ShrinkMethod]::TruncateOnly)
                                            $logfile.Refresh()
                                        } catch {
                                            Write-Progress -id 1 -activity "Backup" -status "Failed" -completed
                                            Stop-Function -Message "Backup failed for database" -ErrorRecord $_ -Target $dbName -Continue -FunctionName Expand-DbaDbLogFile
                                            Continue
                                        }

                                    }
                                    while (($logfile.Size / 1024) -gt $ShrinkSize -and ++$backupRetries -lt 6)

                                    $currentSize = $logfile.Size
                                    $currentSizeMB = $currentSize / 1024
                                    Write-Message -Level Verbose -Message "TLog backup and truncate for database '$dbName' finished. Current TLog size after $backupRetries backups is $($currentSize/1024)MB" -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                                }
                            }
                        }

                        # SMO uses values in KB
                        $SuggestLogIncrementSize = $SuggestLogIncrementSize * 1024

                        # If default, use $SuggestedLogIncrementSize
                        if ($IncrementSize -eq -1) {
                            $LogIncrementSize = $SuggestLogIncrementSize
                        } else {
                            if ($LogIncrementSize -lt $SuggestLogIncrementSize) {
                                Write-Message -Level Warning -Message "The input value for increment size is $([System.Math]::Round($LogIncrementSize / 1024, 0))MB, which is less than the suggested value of $($SuggestLogIncrementSize / 1024)MB." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                            }
                        }

                        # If -TargetVlfCount is specified, calculate optimal increment size to achieve target VLF count
                        if ($TargetVlfCount -gt 0) {
                            # When ShrinkLogFile was used, remeasure VLFs post-shrink as the new baseline
                            if ($ShrinkLogFile) {
                                $vlfCountBaseline = Measure-DbaDbVirtualLogFile -SqlInstance $server -Database $dbName
                                Write-Message -Level Verbose -Message "$step - VLF count after shrinking: $($vlfCountBaseline.Total)" -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                            } else {
                                $vlfCountBaseline = $initialVLFCount
                            }

                            $additionalVlfsAllowed = $TargetVlfCount - $vlfCountBaseline.Total

                            if ($additionalVlfsAllowed -le 0) {
                                Write-Message -Level Warning -Message "$step - Current VLF count ($($vlfCountBaseline.Total)) is already at or above the target VLF count ($TargetVlfCount) for database '$dbName'. Use -ShrinkLogFile to reduce VLF count first, then re-expand." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                                continue
                            }

                            $totalGrowthKB = $TargetLogSizeKB - $currentSize

                            if ($totalGrowthKB -gt 0) {
                                $calculatedIncrementKB = Find-TargetVlfIncrementSize -CurrentSizeKB $currentSize -TargetSizeKB $TargetLogSizeKB -AdditionalVlfsAllowed $additionalVlfsAllowed -SqlMajorVersion $server.Version.Major

                                if ($null -eq $calculatedIncrementKB) {
                                    Write-Message -Level Warning -Message "$step - Cannot achieve target VLF count of $TargetVlfCount for database '$dbName': the VLF budget is too small for the required growth from $currentSizeMB MB to $TargetLogSize MB. Increase -TargetVlfCount or use -ShrinkLogFile to start from a lower base." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                                    continue
                                }

                                $estimatedAdditionalVlfCount = Get-VlfCountForGrowthPlan -InitialSizeKB $currentSize -TargetSizeKB $TargetLogSizeKB -IncrementKB $calculatedIncrementKB -SqlMajorVersion $server.Version.Major
                                Write-Message -Level Verbose -Message "$step - TargetVlfCount ${TargetVlfCount}: overriding increment size to $([Math]::Round($calculatedIncrementKB / 1024.0, 2))MB to add an estimated $estimatedAdditionalVlfCount VLFs (was $([Math]::Round($LogIncrementSize / 1024.0, 2))MB)." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                                $LogIncrementSize = [int]$calculatedIncrementKB
                            }
                        }

                        #start growing file
                        If ($__realCmdlet.ShouldProcess($($server.name), "Starting log growth. Increment chunk size: $($LogIncrementSize/1024)MB for database '$dbName'")) {
                            Write-Message -Level Verbose -Message "Starting log growth. Increment chunk size: $($LogIncrementSize/1024)MB for database '$dbName'" -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"

                            Write-Message -Level Verbose -Message "$step - While current size less than target log size." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"

                            while ($currentSize -lt $TargetLogSizeKB) {

                                Write-Progress `
                                    -Id 2 `
                                    -ParentId 1 `
                                    -Activity "Growing file $logfile on '$dbName' database" `
                                    -PercentComplete ($currentSize / $TargetLogSizeKB * 100) `
                                    -Status "Remaining - $([System.Math]::Round($($($TargetLogSizeKB - $currentSize) / 1024.0), 2)) MB"

                                Write-Message -Level Verbose -Message "$step - Verifying if the log can grow or if it's already at the desired size." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                                if (($TargetLogSizeKB - $currentSize) -lt $LogIncrementSize) {
                                    Write-Message -Level Verbose -Message "$step - Log size is lower than the increment size. Setting current size equals $TargetLogSizeKB." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                                    $currentSize = $TargetLogSizeKB
                                } else {
                                    Write-Message -Level Verbose -Message "$step - Grow the $logfile file in $([System.Math]::Round($($LogIncrementSize / 1024.0), 2)) MB" -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                                    $currentSize += $LogIncrementSize
                                }

                                #When -WhatIf Switch, do not run
                                if ($__realCmdlet.ShouldProcess("$step - File will grow to $([System.Math]::Round($($currentSize/1024.0), 2)) MB", "This action will grow the file $logfile on database $dbName to $([System.Math]::Round($($currentSize/1024.0), 2)) MB .`r`nDo you wish to continue?", "Perform grow")) {
                                    Write-Message -Level Verbose -Message "$step - Set size $logfile to $([System.Math]::Round($($currentSize/1024.0), 2)) MB" -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                                    $logfile.size = $currentSize

                                    Write-Message -Level Verbose -Message "$step - Applying changes" -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                                    $logfile.Alter()
                                    Write-Message -Level Verbose -Message "$step - Changes have been applied" -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"

                                    #Will put the info like VolumeFreeSpace up to date
                                    $logfile.Refresh()
                                }
                            }

                            Write-Message -Level Verbose -Message "`r`n$step - [OK] Growth process for logfile '$logfile' on database '$dbName', has been finished." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"

                            Write-Message -Level Verbose -Message "$step - Grow $logfile log file on $dbName database finished." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                        }
                    }
                }
                #else verifying existence
                else {
                    Write-Message -Level Verbose -Message "Database '$dbName' does not exist on instance '$SqlInstance'." -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
                }

                #Get the number of VLFs
                $currentVLFCount = Measure-DbaDbVirtualLogFile -SqlInstance $server -Database $dbName

                [PSCustomObject]@{
                    ComputerName    = $server.ComputerName
                    InstanceName    = $server.ServiceName
                    SqlInstance     = $server.DomainInstanceName
                    Database        = $dbName
                    DatabaseID      = $db.ID
                    ID              = $logfile.ID
                    Name            = $logfile.Name
                    LogFileCount    = $numLogfiles
                    InitialSize     = [dbasize]($currentSizeMB * 1024 * 1024)
                    CurrentSize     = [dbasize]($TargetLogSize * 1024 * 1024)
                    InitialVLFCount = $initialVLFCount.Total
                    CurrentVLFCount = $currentVLFCount.Total
                } | Select-DefaultView -ExcludeProperty LogFileCount
            } #foreach database
        } catch {
            Stop-Function -Message "Logfile $logfile on database $dbName not processed. Error: $($_.Exception.Message). Line Number:  $($_InvocationInfo.ScriptLineNumber)" -Continue -FunctionName Expand-DbaDbLogFile
        }
    }

        Write-Message -Level Verbose -Message "Process finished $((Get-Date) - ($initialTime))" -FunctionName Expand-DbaDbLogFile -ModuleName "dbatools"
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $TargetLogSize $IncrementSize $TargetVlfCount $LogFileId $ShrinkLogFile $ShrinkSize $BackupDirectory $ExcludeDiskSpaceValidation $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Deletes data from a table in batches, optionally backing up the log between batches. Port of
/// public/Remove-DbaDbTableData.ps1; the workflow remains a module-scoped PowerShell compatibility
/// hop.
///
/// The source's three phases are modelled as three phases. BeginProcessing runs the begin body once,
/// ProcessRecord runs the process body per record, and the state begin produces crosses between them
/// on a sentinel. That is not stylistic: begin holds SIX hard Stop-Function guards, and the function
/// runs begin even when the pipeline turns out to be EMPTY, so deferring it into the first
/// ProcessRecord would skip those guards entirely for "@() | Remove-DbaDbTableData" and would also
/// run them after the upstream command's first record rather than before it.
///
/// Two distinct mechanisms are needed to stop later records, and this row is the case that shows why
/// one is not enough:
///   * begin runs ONCE, so its parameter guards fire once - a latch cannot do this, because those
///     guards never consult the interrupt;
///   * the graceful-stop latch is carried so the PROCESS body's own Test-FunctionInterrupt guards
///     short-circuit records after a stop. Nothing bridges an in-hop Stop-Function to the base
///     cmdlet's Interrupted flag, which only the C# StopFunction helper raises.
/// An earlier build carried the latch but still folded begin per record; measured, the function
/// warned once across 3 and 5 records while the port warned 3 and 5 times.
///
/// Test-Bound cannot ride the hop - inside one the caller is the scriptblock, so every call would
/// report the parameter unbound and each guard it protects would silently stop firing. All ten call
/// sites are flag-substituted; the generator hard-fails if any Test-Bound string survives.
///
/// The two values begin produces - $sql and the defaulted $LogBackupTimeStampFormat - are read by
/// the process body and therefore cross on the sentinel. They are read out of the begin hop with
/// Get-Variable rather than directly, because the six guards return before $sql is ever assigned and
/// that carrier runs on every path, including those; a bare read there would fail under StrictMode
/// on a path the function never reads on.
///
/// The single ShouldProcess gate is routed to the OUTER cmdlet, keeping -Confirm's "Yes to All"
/// alive across records; ConfirmImpact is High. -BatchSize keeps ValidateRange(1, 1000000000) and
/// its 100000 default.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDbTableData", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed class RemoveDbaDbTableDataCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database or databases holding the table.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>How many rows to delete per batch.</summary>
    [Parameter(Position = 3)]
    [ValidateRange(1, 1000000000)]
    public int BatchSize { get; set; } = 100000;

    /// <summary>The table to delete from.</summary>
    [Parameter(Position = 4)]
    public string? Table { get; set; }

    /// <summary>A custom DELETE statement, which must carry a TOP (N) clause.</summary>
    [Parameter(Position = 5)]
    public string? DeleteSql { get; set; }

    /// <summary>Where to write log backups taken between batches.</summary>
    [Parameter(Position = 6)]
    public string? LogBackupPath { get; set; }

    /// <summary>Timestamp format for log backup file names.</summary>
    [Parameter(Position = 7)]
    public string? LogBackupTimeStampFormat { get; set; }

    /// <summary>Azure blob base URL for log backups.</summary>
    [Parameter(Position = 8)]
    public string[]? AzureBaseUrl { get; set; }

    /// <summary>The SQL credential used for Azure blob log backups.</summary>
    [Parameter(Position = 9)]
    public string? AzureCredential { get; set; }

    /// <summary>Database objects, typically from Get-DbaDatabase.</summary>
    [Parameter(Position = 10, ValueFromPipeline = true)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // State produced by the begin phase and read by the process body, plus the graceful-stop latch.
    private bool _interrupted;
    private object? _sql;
    private object? _logBackupTimeStampFormat;

    protected override void BeginProcessing()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__removeDbaDbTableDataState"]?.Value))
            {
                _interrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
                _sql = item.Properties["Sql"]?.Value;
                _logBackupTimeStampFormat = item.Properties["LogBackupTimeStampFormat"]?.Value;
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
            BatchSize, Table, DeleteSql, LogBackupPath, LogBackupTimeStampFormat, AzureBaseUrl,
            EnableException.ToBool(),
            TestBound(nameof(Table)), TestBound(nameof(DeleteSql)), TestBound(nameof(BatchSize)),
            TestBound(nameof(LogBackupPath)), TestBound(nameof(AzureBaseUrl)),
            TestBound(nameof(LogBackupTimeStampFormat)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__removeDbaDbTableDataState"]?.Value))
            {
                _interrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
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
            SqlInstance, SqlCredential, Database, BatchSize, Table, DeleteSql, LogBackupPath,
            AzureBaseUrl, AzureCredential, InputObject, EnableException.ToBool(), this,
            _interrupted, _sql, _logBackupTimeStampFormat,
            TestBound(nameof(LogBackupPath)), TestBound(nameof(AzureBaseUrl)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source's BEGIN body VERBATIM, run once. Substitutions only: the six Test-Bound call
    // sites -> flags, and -FunctionName on Stop-Function/Write-Message.
    private const string BeginScript = """
param($BatchSize, $Table, $DeleteSql, $LogBackupPath, $LogBackupTimeStampFormat, $AzureBaseUrl, $EnableException, $__boundTable, $__boundDeleteSql, $__boundBatchSize, $__boundLogBackupPath, $__boundAzureBaseUrl, $__boundLogBackupTimeStampFormat, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([int]$BatchSize, [string]$Table, [string]$DeleteSql, [string]$LogBackupPath, [string]$LogBackupTimeStampFormat, [string[]]$AzureBaseUrl, $EnableException, $__boundTable, $__boundDeleteSql, $__boundBatchSize, $__boundLogBackupPath, $__boundAzureBaseUrl, $__boundLogBackupTimeStampFormat, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    try {

        if (($__boundTable) -and ($__boundDeleteSql)) {
            Stop-Function -Message "You must specify either -Table or -DeleteSql, but not both. See the command description for more details." -FunctionName Remove-DbaDbTableData
            return
        }

        if (-not $Table -and -not $DeleteSql) {
            Stop-Function -Message "You must specify either -Table or -DeleteSql. See the command description for more details." -FunctionName Remove-DbaDbTableData
            return
        }

        if (($__boundBatchSize) -and ($__boundDeleteSql)) {
            Stop-Function -Message "When using -DeleteSql the -BatchSize param cannot be used. See the command description for more details." -FunctionName Remove-DbaDbTableData
            return
        }

        if (($__boundLogBackupPath) -and ($__boundAzureBaseUrl)) {
            Stop-Function -Message "You must specify either -LogBackupPath or -AzureBaseUrl, but not both. See the command description for more details." -FunctionName Remove-DbaDbTableData
            return
        }

        if ($__boundDeleteSql) {
            if ($DeleteSql -inotmatch "top") {
                Stop-Function -Message "To use the -DeleteSql param you must specify the TOP (N) clause in the DELETE statement. See the command description for more details." -FunctionName Remove-DbaDbTableData
                return
            }

            if ($DeleteSql -inotmatch "delete") {
                Stop-Function -Message "The -DeleteSql param must be a DELETE statement with a TOP (N) clause. See the command description for more details." -FunctionName Remove-DbaDbTableData
                return
            }
        }

        if (-not ($__boundLogBackupTimeStampFormat)) {
            Write-Message -Message 'Setting Default LogBackupTimeStampFormat' -Level Verbose -FunctionName Remove-DbaDbTableData -ModuleName "dbatools"
            $LogBackupTimeStampFormat = "yyyyMMddHHmm"
        }

        # build the delete statement based on the caller's parameters
        $sql = "
            SET DEADLOCK_PRIORITY LOW;
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            DECLARE
                @RowCount       INTEGER         = 0
            ,   @ErrorMessage   NVARCHAR(MAX)   = NULL;

            BEGIN TRANSACTION;

            BEGIN TRY
            "

        if ($__boundTable) {
            $nameParts = Get-ObjectNameParts -ObjectName $Table
            if (-not $nameParts.Parsed) {
                Stop-Function -Message "Please check you are using proper one-, two-, or three-part names. If your table name contains special characters you must use [ ] to wrap the name. The value $Table could not be parsed as a valid table name." -FunctionName Remove-DbaDbTableData
                return
            }

            $quotedTableName = "[" + $nameParts.Name.Replace("]", "]]") + "]"
            if ($nameParts.Database) {
                $quotedDatabaseName = "[" + $nameParts.Database.Replace("]", "]]") + "]"

                if ($nameParts.Schema) {
                    $quotedSchemaName = "[" + $nameParts.Schema.Replace("]", "]]") + "]"
                    $bracketedTable = "$quotedDatabaseName.$quotedSchemaName.$quotedTableName"
                } else {
                    $bracketedTable = "$quotedDatabaseName..$quotedTableName"
                }
            } elseif ($nameParts.Schema) {
                $quotedSchemaName = "[" + $nameParts.Schema.Replace("]", "]]") + "]"
                $bracketedTable = "$quotedSchemaName.$quotedTableName"
            } else {
                $bracketedTable = $quotedTableName
            }
            $sql += "    DELETE TOP ($BatchSize) FROM $bracketedTable;"
        } elseif ($__boundDeleteSql) {
            $sql += "    $DeleteSql;"
        }

        $sql += "
                SET @RowCount = @@ROWCOUNT;
                COMMIT TRANSACTION;
            END TRY
            BEGIN CATCH
                SET @ErrorMessage = 'Error number = ' + CAST(ERROR_NUMBER() AS NVARCHAR(MAX)) +
                                    ', Severity = ' + CAST(ERROR_SEVERITY() AS NVARCHAR(MAX)) +
                                    ', Line = ' + CAST(ERROR_LINE() AS NVARCHAR(MAX)) +
                                    ', Message = ' + CAST(ERROR_MESSAGE() AS NVARCHAR(MAX));

                IF @@TRANCOUNT > 0
                    ROLLBACK TRANSACTION;
            END CATCH;

            SELECT
                @RowCount       AS [RowCount]
            ,   @ErrorMessage   AS ErrorMessage;"

    } finally {
        # Read via Get-Variable: the six guards above return before $sql is ever assigned, and this
        # carrier runs on every path including those. A bare read would fail under StrictMode on a
        # path the function never reads on.
        [pscustomobject]@{
            __removeDbaDbTableDataState = $true
            Interrupted                 = [bool](Test-FunctionInterrupt)
            Sql                         = (Get-Variable -Name 'sql' -Scope 0 -ValueOnly -ErrorAction Ignore)
            LogBackupTimeStampFormat    = (Get-Variable -Name 'LogBackupTimeStampFormat' -Scope 0 -ValueOnly -ErrorAction Ignore)
        }
    }
} $BatchSize $Table $DeleteSql $LogBackupPath $LogBackupTimeStampFormat $AzureBaseUrl $EnableException $__boundTable $__boundDeleteSql $__boundBatchSize $__boundLogBackupPath $__boundAzureBaseUrl $__boundLogBackupTimeStampFormat $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the source's PROCESS body VERBATIM, seeded with what begin produced. Substitutions only:
    // the two Test-Bound call sites in this body -> flags, $Pscmdlet/$PSCmdlet -> $__realCmdlet, and
    // -FunctionName on Stop-Function/Write-Message.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $BatchSize, $Table, $DeleteSql, $LogBackupPath, $AzureBaseUrl, $AzureCredential, $InputObject, $EnableException, $__realCmdlet, $__carriedInterrupt, $__carriedSql, $__carriedLogBackupTimeStampFormat, $__boundLogBackupPath, $__boundAzureBaseUrl, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [int]$BatchSize, [string]$Table, [string]$DeleteSql, [string]$LogBackupPath, [string[]]$AzureBaseUrl, [string]$AzureCredential, [object[]]$InputObject, $EnableException, $__realCmdlet, $__carriedInterrupt, $__carriedSql, $__carriedLogBackupTimeStampFormat, $__boundLogBackupPath, $__boundAzureBaseUrl, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # What the begin phase produced, and the stop latch it may have set.
    $sql = $__carriedSql
    $LogBackupTimeStampFormat = $__carriedLogBackupTimeStampFormat
    if ($__carriedInterrupt) {
        Set-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -Scope 0 -Value $true
    }

    try {

        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must specify a SqlInstance or pipe in a database or a server. See the command description." -FunctionName Remove-DbaDbTableData
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName
            switch ($inputType) {
                # get the db(s) based on the caller's parameters
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject" -FunctionName Remove-DbaDbTableData -ModuleName "dbatools"
                    $dbDatabases = Get-DbaDatabase -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeSystem
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject" -FunctionName Remove-DbaDbTableData -ModuleName "dbatools"
                    $dbDatabases = Get-DbaDatabase -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeSystem
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject" -FunctionName Remove-DbaDbTableData -ModuleName "dbatools"
                    $dbDatabases = $input | Where-Object { -not $_.IsSystemObject }
                }
                default {
                    Stop-Function -Message "InputObject is not a server or database. See the command description for examples." -FunctionName Remove-DbaDbTableData
                    return
                }
            }

            foreach ($db in $dbDatabases) {

                $server = $db.Parent

                if ($__boundLogBackupPath -and $server.DatabaseEngineType -ne "SqlAzureDatabase") {
                    $pathCheck = Test-DbaPath -SqlInstance $server -Path $LogBackupPath
                    if (-not $pathCheck) {
                        Stop-Function -Message "The service account for $server is not able to create log backups in $LogBackupPath." -FunctionName Remove-DbaDbTableData
                        return
                    }
                }

                # warn the caller if the database is using one of these configurations for on-prem
                if ($server.DatabaseEngineType -ne "SqlAzureDatabase") {

                    $isDbLogShipping = $db.Query("SELECT COUNT(1) FROM msdb.dbo.log_shipping_monitor_primary WHERE primary_database = '$($db.Name)'")

                    if ($isDbLogShipping -eq 1) {
                        Write-Message -Level Warning -Message "$($db.Name) is the primary db in a log shipping configuration. Be sure to re-sync after this command completes." -FunctionName Remove-DbaDbTableData -ModuleName "dbatools"
                    }

                    if ($db.IsMirroringEnabled) {
                        Write-Message -Level Warning -Message "$($db.Name) is configured for mirroring. Be sure to validate the mirror is synchronized after this command completes." -FunctionName Remove-DbaDbTableData -ModuleName "dbatools"
                    }

                    if (-not [string]::IsNullOrEmpty($db.AvailabilityGroupName)) {
                        Write-Message -Level Warning -Message "$($db.Name) is part of an availability group. Be sure to validate the secondary database(s) is synchronized after this command completes." -FunctionName Remove-DbaDbTableData -ModuleName "dbatools"
                    }
                }

                if ($__realCmdlet.ShouldProcess($db.Name, "Removing data using $sql on $($db.Parent.Name)")) {

                    # metadata to collect while running the loop
                    $totalRowsDeleted = 0
                    $totalTimeMillis = 0
                    $iterationCount = 0
                    $logBackupsArray = @()
                    $timingsArray = @()

                    do {
                        $rowCount = 0

                        try {
                            $commandTiming = Measure-Command {
                                $result = $db.Query($sql)
                            }

                            # Check if a runtime error occurred during the delete. Malformed SQL errors skip over this and end up in the catch block below.
                            if (-not [string]::IsNullOrEmpty($result.ErrorMessage)) {
                                throw $result.ErrorMessage
                            }

                            $rowCount = $result.RowCount

                            if ($rowCount -gt 0) {
                                # rows were deleted on the last statement execution, so collect the metadata and print out a verbose message.
                                $totalRowsDeleted += $rowCount
                                $timingsArray += $commandTiming
                                $totalTimeMillis += $commandTiming.TotalMilliseconds

                                Write-Message -Level Verbose -Message "Iteration $iterationCount took $($commandTiming.TotalMilliseconds) milliseconds to remove $rowCount rows" -FunctionName Remove-DbaDbTableData -ModuleName "dbatools"
                            }
                        } catch {
                            Stop-Function -Message "Error removing data from $Table $DeleteSql using $sql on $($db.Parent.Name)" -ErrorRecord $_ -FunctionName Remove-DbaDbTableData
                            return
                        }

                        if ($rowCount -gt 0) {
                            $iterationCount += 1

                            #If the db is in Azure then we won't do a checkpoint or a log backup since those are automatically managed.
                            if ($server.DatabaseEngineType -ne "SqlAzureDatabase") {

                                if ($db.RecoveryModel -eq "Simple") {
                                    try {
                                        $checkPointResult = $db.Query("CHECKPOINT")

                                        if (-not [string]::IsNullOrEmpty($checkPointResult.ErrorMessage)) {
                                            throw $checkPointResult.ErrorMessage
                                        }
                                    } catch {
                                        Stop-Function -Message "Error during checkpoint on $($db.Parent.Name)" -ErrorRecord $_ -FunctionName Remove-DbaDbTableData
                                        return
                                    }

                                } else {
                                    # bulk-logged or full recovery model

                                    if ($__boundLogBackupPath) {
                                        $timestamp = Get-Date -Format $LogBackupTimeStampFormat
                                        $logBackupsArray += Backup-DbaDatabase -SqlInstance $server -Database $db.Name -Type Log -FilePath "$LogBackupPath\$($db.Name)_$($timestamp)_$($iterationCount).trn"
                                    } elseif ($__boundAzureBaseUrl) {
                                        $logBackupsArray += Backup-DbaDatabase -SqlInstance $server -Database $db.Name -Type Log -AzureBaseUrl $AzureBaseUrl -AzureCredential $AzureCredential
                                    }
                                }
                            }
                        }

                        if (Test-FunctionInterrupt) { return }

                    } while ($rowCount -gt 0)

                    [PSCustomObject]@{
                        ComputerName     = $db.Parent.ComputerName
                        InstanceName     = $db.Parent.Name
                        Database         = $db.Name
                        Sql              = $sql
                        TotalRowsDeleted = $totalRowsDeleted
                        Timings          = $timingsArray
                        TotalTimeMillis  = $totalTimeMillis
                        AvgTimeMillis    = $totalTimeMillis / $(if ($iterationCount -le 0) { 1 } else { $iterationCount })
                        TotalIterations  = $iterationCount
                        LogBackups       = $logBackupsArray

                    } | Select-DefaultView -Property "ComputerName", "InstanceName", "Database", "Sql", "TotalRowsDeleted", "TotalTimeMillis", "AvgTimeMillis", "TotalIterations"
                }
            }
        }

    } finally {
        [pscustomobject]@{
            __removeDbaDbTableDataState = $true
            Interrupted                 = [bool](Test-FunctionInterrupt)
        }
    }
} $SqlInstance $SqlCredential $Database $BatchSize $Table $DeleteSql $LogBackupPath $AzureBaseUrl $AzureCredential $InputObject $EnableException $__realCmdlet $__carriedInterrupt $__carriedSql $__carriedLogBackupTimeStampFormat $__boundLogBackupPath $__boundAzureBaseUrl $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

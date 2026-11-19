#nullable enable

namespace Dataplat.Dbatools.Commands;

// Hop script constants (the verbatim retired PS bodies) - split out per the repo 400-line file limit.
public sealed partial class GetDbaDatabaseCommand
{

    // PS: the begin block, dot-sourced. Edits are -FunctionName on the guard and a live warning
    // sink for the top-level -Continue path. The guard does not set the latch; the sentinel still
    // carries the interrupt for uniformity. Begin holds no value state that process depends on.
    private const string BeginScript = """
param($ExcludeUser, $ExcludeSystem, $EnableException, $__boundVerbose, $__boundDebug, $__guardWarningSink)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($ExcludeUser, $ExcludeSystem, $EnableException, $__boundVerbose, $__boundDebug, $__guardWarningSink)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {

        if ($ExcludeUser -and $ExcludeSystem) {
            $__guardWarningPreference = $WarningPreference
            try {
                if ($__guardWarningPreference -in @("SilentlyContinue", "Inquire")) {
                    $WarningPreference = "Continue"
                }
                Stop-Function -Message "You cannot specify both ExcludeUser and ExcludeSystem." -Continue -EnableException $EnableException -FunctionName Get-DbaDatabase 3>&1 | ForEach-Object { if ($PSItem -is [System.Management.Automation.WarningRecord]) { $null = $__guardWarningSink.Add($PSItem.Message) } }
            } finally {
                $WarningPreference = $__guardWarningPreference
            }
        }

    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __getDbaDatabaseBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $ExcludeUser $ExcludeSystem $EnableException $__boundVerbose $__boundDebug $__guardWarningSink @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM, dot-sourced so the :252 early return exits only the body.
    // Edits: Test-Bound -Parameter 'Encrypted' becomes $__boundEncrypted, plus -FunctionName stamps.
    // The in-process helper functions (Invoke-QueryDBlastUsed / Invoke-QueryRawDatabases /
    // Invoke-QueryDatabaseSizes / $matchesPattern) ride verbatim. The latch is read at Scope 0 after
    // the body so a :351 Failure on this record silences later records.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Pattern, $ExcludeUser, $ExcludeSystem, $Owner, $Encrypted, $Status, $Access, $RecoveryModel, $NoFullBackup, $NoFullBackupSince, $NoLogBackup, $NoLogBackupSince, $IncludeLastUsed, $OnlyAccessible, $EnableException, $__boundEncrypted, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$ExcludeDatabase, [string[]]$Pattern, $ExcludeUser, $ExcludeSystem, [string[]]$Owner, $Encrypted, [string[]]$Status, [string]$Access, [string[]]$RecoveryModel, $NoFullBackup, $NoFullBackupSince, $NoLogBackup, $NoLogBackupSince, $IncludeLastUsed, $OnlyAccessible, $EnableException, $__boundEncrypted, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Get-DbaDatabase
            }

            if (!$IncludeLastUsed) {
                $dblastused = $null
            } else {
                ## Get last used information from the DMV
                $querylastused = "WITH agg AS
                (
                  SELECT
                       MAX(last_user_seek) last_user_seek,
                       MAX(last_user_scan) last_user_scan,
                       MAX(last_user_lookup) last_user_lookup,
                       MAX(last_user_update) last_user_update,
                       sd.name dbname
                   FROM
                       sys.dm_db_index_usage_stats, master..sysdatabases sd
                   WHERE
                     database_id = sd.dbid AND database_id > 4
                      GROUP BY sd.name
                )
                SELECT
                   dbname,
                   last_read = MAX(last_read),
                   last_write = MAX(last_write)
                FROM
                (
                   SELECT dbname, last_user_seek, NULL FROM agg
                   UNION ALL
                   SELECT dbname, last_user_scan, NULL FROM agg
                   UNION ALL
                   SELECT dbname, last_user_lookup, NULL FROM agg
                   UNION ALL
                   SELECT dbname, NULL, last_user_update FROM agg
                ) AS x (dbname, last_read, last_write)
                GROUP BY
                   dbname
                ORDER BY 1;"
                # put a function around this to enable Pester Testing and also to ease any future changes
                function Invoke-QueryDBlastUsed {
                    $server.Query($querylastused)
                }
                $dblastused = Invoke-QueryDBlastUsed
            }

            if ($ExcludeUser) {
                $DBType = @($true)
            } elseif ($ExcludeSystem) {
                $DBType = @($false)
            } else {
                $DBType = @($false, $true)
            }

            $AccessibleFilter = switch ($OnlyAccessible) {
                $true { @($true) }
                default { @($true, $false) }
            }

            $Readonly = switch ($Access) {
                'Readonly' { @($true) }
                'ReadWrite' { @($false) }
                default { @($true, $false) }
            }
            $Encrypt = switch ($__boundEncrypted) {
                $true { @($true) }
                default { @($true, $false, $null) }
            }
            function Invoke-QueryRawDatabases {
                try {
                    if ($server.isAzure) {
                        $dbquery = "SELECT db.name, db.state, dp.name AS [Owner] FROM sys.databases AS db LEFT JOIN sys.database_principals AS dp ON dp.sid = db.owner_sid"
                        $server.ConnectionContext.ExecuteWithResults($dbquery).Tables
                    } elseif ($server.VersionMajor -eq 8) {
                        $server.Query("
                            SELECT name,
                                CASE DATABASEPROPERTYEX(name,'status')
                                    WHEN 'ONLINE'     THEN 0
                                    WHEN 'RESTORING'  THEN 1
                                    WHEN 'RECOVERING' THEN 2
                                    WHEN 'SUSPECT'    THEN 4
                                    WHEN 'EMERGENCY'  THEN 5
                                    WHEN 'OFFLINE'    THEN 6
                                END AS state,
                                SUSER_SNAME(sid) AS [Owner]
                            FROM master.dbo.sysdatabases
                        ")
                    } elseif ($server.VersionMajor -eq 9) {
                        # CDC did not exist in version 9, but did afterwards.
                        $server.Query("SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner] FROM sys.databases")
                    } else {
                        $server.Query("SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner], is_cdc_enabled FROM sys.databases")
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -FunctionName Get-DbaDatabase
                }
            }

            $backed_info = Invoke-QueryRawDatabases

            # Helper function to test if a name matches any of the provided regex patterns
            $matchesPattern = {
                param($name, $patterns)
                if (!$patterns) { return $true }
                foreach ($pattern in $patterns) {
                    if ($name -match $pattern) { return $true }
                }
                return $false
            }

            $backed_info = $backed_info | Where-Object {
                ($_.name -in $Database -or !$Database) -and
                ($_.name -notin $ExcludeDatabase -or !$ExcludeDatabase) -and
                (& $matchesPattern $_.name $Pattern) -and
                ($_.Owner -in $Owner -or !$Owner) -and
                ($_.state -ne 6 -or !$OnlyAccessible)
            }


            $inputObject = @()
            foreach ($dt in $backed_info) {
                try {
                    $inputObject += $server.Databases | Where-Object Name -ceq $dt.name
                } catch {
                    # I've seen this only once and can not reproduce:
                    # The following exception occurred while trying to enumerate the collection: "Failed to connect to server XXXXX.database.windows.net.".
                    # So we implement the fallback that was used before #8333.
                    Write-Message -Level Verbose -Message "Failure: $_" -FunctionName Get-DbaDatabase -ModuleName "dbatools"
                    $inputObject += $server.Databases[$dt.name]
                }
            }
            if ($server.isAzure) {
                $inputObject = $inputObject |
                    Where-Object {
                        ($_.Name -in $Database -or !$Database) -and
                        ($_.Name -notin $ExcludeDatabase -or !$ExcludeDatabase) -and
                        (& $matchesPattern $_.Name $Pattern) -and
                        ($_.Owner -in $Owner -or !$Owner) -and
                        ($_.RecoveryModel -in $RecoveryModel -or !$_.RecoveryModel) -and
                        $_.EncryptionEnabled -in $Encrypt
                    }
            } else {
                $inputObject = $inputObject |
                    Where-Object {
                        ($_.Name -in $Database -or !$Database) -and
                        ($_.Name -notin $ExcludeDatabase -or !$ExcludeDatabase) -and
                        (& $matchesPattern $_.Name $Pattern) -and
                        ($_.Owner -in $Owner -or !$Owner) -and
                        $_.ReadOnly -in $Readonly -and
                        $_.IsAccessible -in $AccessibleFilter -and
                        $_.IsSystemObject -in $DBType -and
                        ((Compare-Object @($_.Status.tostring().split(',').trim()) $Status -ExcludeDifferent -IncludeEqual).inputobject.count -ge 1 -or !$status) -and
                        ($_.RecoveryModel -in $RecoveryModel -or !$_.RecoveryModel) -and
                        $_.EncryptionEnabled -in $Encrypt
                    }
            }
            if ($NoFullBackup -or $NoFullBackupSince) {
                $lastFullBackups = Get-DbaDbBackupHistory -SqlInstance $server -LastFull
                $lastCopyOnlyBackups = Get-DbaDbBackupHistory -SqlInstance $server -LastFull -IncludeCopyOnly | Where-Object IsCopyOnly
                if ($NoFullBackupSince) {
                    $lastFullBackups = $lastFullBackups | Where-Object End -gt $NoFullBackupSince
                    $lastCopyOnlyBackups = $lastCopyOnlyBackups | Where-Object End -gt $NoFullBackupSince
                }

                $hasCopyOnly = $inputObject | Compare-DbaCollationSensitiveObject -Property Name -In -Value $lastCopyOnlyBackups.Database -Collation $server.Collation
                $inputObject = $inputObject | Where-Object Name -cne 'tempdb'
                $inputObject = $inputObject | Compare-DbaCollationSensitiveObject -Property Name -NotIn -Value $lastFullBackups.Database -Collation $server.Collation
            }
            if ($NoLogBackup -or $NoLogBackupSince) {
                if (!$NoLogBackupSince) {
                    $NoLogBackupSince = New-Object -TypeName DateTime
                    $NoLogBackupSince = $NoLogBackupSince.AddMilliSeconds(1)
                }
                $inputObject = $inputObject | Where-Object { $_.LastLogBackupDate -lt $NoLogBackupSince -and $_.RecoveryModel -ne 'Simple' }
            }

            $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Status', 'IsAccessible', 'RecoveryModel',
            'LogReuseWaitStatus', 'Size as SizeMB', 'CompatibilityLevel as Compatibility', 'Collation', 'Owner', 'EncryptionEnabled as Encrypted',
            'LastBackupDate as LastFullBackup', 'LastDifferentialBackupDate as LastDiffBackup',
            'LastLogBackupDate as LastLogBackup'

            if ($NoFullBackup -or $NoFullBackupSince) {
                $defaults += ('BackupStatus')
            }
            if ($IncludeLastUsed) {
                # Add Last Used to the default view
                $defaults += ('LastRead as LastIndexRead', 'LastWrite as LastIndexWrite')
            }

            # Get database sizes via T-SQL for fallback when SMO Size is null/0
            # This query works for SQL Server 2000+ and calculates size from sys.master_files or sysaltfiles
            # Azure SQL Database doesn't have sys.master_files, so we use sys.database_files instead
            $querySizes = if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                # Azure SQL Database doesn't have sys.master_files
                # Use sys.database_files which is database-scoped
                "SELECT DB_NAME() AS name,
                    CAST(SUM(CAST(size AS BIGINT)) * 8.0 / 1024 AS DECIMAL(18,2)) AS SizeMB
                FROM sys.database_files"
            } elseif ($server.VersionMajor -ge 9) {
                "SELECT DB_NAME(database_id) AS name,
                    CAST(SUM(CAST(size AS BIGINT)) * 8.0 / 1024 AS DECIMAL(18,2)) AS SizeMB
                FROM sys.master_files
                GROUP BY database_id"
            } else {
                "SELECT dbname = DB_NAME(dbid),
                    SizeMB = CAST(SUM(CAST(size AS BIGINT)) * 8.0 / 1024 AS DECIMAL(18,2))
                FROM master.dbo.sysaltfiles
                GROUP BY dbid"
            }

            function Invoke-QueryDatabaseSizes {
                try {
                    if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                        # For Azure, we need to query each database individually
                        # since sys.database_files is database-scoped
                        $results = @()
                        foreach ($db in $inputObject) {
                            try {
                                $splatQuery = @{
                                    SqlInstance     = $server
                                    Database        = $db.Name
                                    Query           = $querySizes
                                    EnableException = $true
                                }
                                $result = Invoke-DbaQuery @splatQuery
                                if ($result) {
                                    $results += $result
                                }
                            } catch {
                                # Skip databases that can't be queried (offline, etc.)
                            }
                        }
                        $results
                    } else {
                        $server.Query($querySizes)
                    }
                } catch {
                    Write-Message -Level Warning -Message "Could not retrieve database sizes via T-SQL: $_" -FunctionName Get-DbaDatabase -ModuleName "dbatools"
                    $null
                }
            }

            $dbSizes = Invoke-QueryDatabaseSizes

            try {
                foreach ($db in $inputObject) {

                    $backupStatus = $null
                    if ($NoFullBackup -or $NoFullBackupSince) {
                        if ($db -cin $hasCopyOnly) {
                            $backupStatus = "Only CopyOnly backups"
                        }
                    }

                    # Use T-SQL size if SMO Size is null or 0
                    $sizeValue = $db.Size
                    if ($null -eq $sizeValue -or $sizeValue -eq 0) {
                        $dbSizeInfo = $dbSizes | Where-Object { $_.name -eq $db.Name }
                        if ($dbSizeInfo) {
                            $sizeValue = $dbSizeInfo.SizeMB
                        }
                    }

                    $lastusedinfo = $dblastused | Where-Object { $_.dbname -eq $db.name }
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name BackupStatus -Value $backupStatus
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name LastRead -Value $lastusedinfo.last_read
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name LastWrite -Value $lastusedinfo.last_write
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name IsCdcEnabled -Value ($backed_info | Where-Object { $_.name -ceq $db.name }).is_cdc_enabled
                    # Override Size property with calculated value if SMO returned null/0
                    if ($null -ne $sizeValue) {
                        Add-Member -Force -InputObject $db -MemberType NoteProperty -Name Size -Value $sizeValue
                    }
                    Select-DefaultView -InputObject $db -Property $defaults
                }
            } catch {
                Stop-Function -ErrorRecord $_ -Target $instance -Message "Failure. Collection may have been modified. If so, please use parens (Get-DbaDatabase ....) | when working with commands that modify the collection such as Remove-DbaDatabase." -Continue -FunctionName Get-DbaDatabase
            }
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __getDbaDatabaseProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Pattern $ExcludeUser $ExcludeSystem $Owner $Encrypted $Status $Access $RecoveryModel $NoFullBackup $NoFullBackupSince $NoLogBackup $NoLogBackupSince $IncludeLastUsed $OnlyAccessible $EnableException $__boundEncrypted $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

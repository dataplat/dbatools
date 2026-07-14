function Test-DbaBackupStorageCompatibility {
    <#
    .SYNOPSIS
        Estimates whether recent database backups fit cloud storage limits.

    .DESCRIPTION
        Evaluates the most recent full backup for each selected database against the limits of a cloud backup storage provider. The initial provider is S3-compatible object storage for SQL Server 2022 and later.

        S3-compatible SQL Server backups support at most 64 URLs and 10,000 multipart upload parts per URL. This command estimates parts per URL by evenly dividing the effective backup size across the backup file count. It uses compressed size when the backup history reports one, otherwise it uses the uncompressed size.

        The estimate helps identify backup configurations that need more URLs, a larger MAXTRANSFERSIZE, or compression before moving to S3-compatible storage. It does not validate credentials, network access, or a specific object storage implementation.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. S3-compatible backup evaluation requires SQL Server 2022 or later.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies one or more databases to evaluate. By default, all accessible databases with full backup history are evaluated.

    .PARAMETER ExcludeDatabase
        Specifies one or more databases to exclude from evaluation.

    .PARAMETER Type
        Specifies the cloud backup storage provider. The only currently supported value, and the default, is S3.

    .PARAMETER MaxTransferSize
        Specifies the MAXTRANSFERSIZE value in bytes used to estimate multipart upload parts. S3-compatible SQL Server backups support values from 5 MiB through 20 MiB. The default is 10 MiB (10485760 bytes).

        Values other than 10 MiB require backup compression when the backup is written.

    .PARAMETER Threshold
        Specifies the percentage of the 10,000-part limit at which a compatible backup is reported as Warning. The default is 90.

    .PARAMETER Monitor
        Returns only Warning or incompatible results. After returning those results, signals an InvalidResult through Stop-Function when one or more risks were found.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Backup, S3, Cloud, AWS
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaBackupStorageCompatibility

    .OUTPUTS
        PSCustomObject

        Returns one estimate per database with full backup history. With -Monitor, returns only Warning or incompatible estimates.

        Properties:
        - ComputerName: Computer name of the SQL Server instance (string)
        - InstanceName: SQL Server service name (string)
        - SqlInstance: Full SQL Server instance name (string)
        - Database: Database evaluated (string)
        - Type: Storage provider evaluated; currently S3 (string)
        - LastFullBackup: Start time of the most recent full backup (DateTime)
        - BackupSizeBytes: Uncompressed backup size in bytes (decimal)
        - CompressedBackupSizeBytes: Compressed backup size in bytes, or zero when unavailable (decimal)
        - EffectiveBackupSizeBytes: Size used for the estimate; compressed size when available, otherwise uncompressed size (decimal)
        - BackupFileCount: Number of files in the backup set (int)
        - MaxTransferSize: MAXTRANSFERSIZE used for the estimate, in bytes (long)
        - EstimatedPartsPerFile: Estimated multipart upload parts for each evenly striped backup file (long)
        - PercentOfLimit: Estimated parts as a percentage of the 10,000-part S3 limit (decimal)
        - IsCompatible: Whether the estimate is within both the part and 64-URL limits (bool)
        - Status: Compatible, Warning, ExceedsPartLimit, ExceedsFileLimit, or ExceedsLimits (string)
        - RecommendedFileCount: Suggested number of backup URLs when calculable, otherwise null (int)
        - RecommendedMaxTransferSizeBytes: Suggested MAXTRANSFERSIZE in bytes when calculable, otherwise null (long)
        - Recommendation: Conservative configuration guidance for Warning or incompatible estimates, otherwise null (string)

    .EXAMPLE
        PS C:\> Test-DbaBackupStorageCompatibility -SqlInstance sql2022

        Evaluates the most recent full backup for every accessible database on sql2022 using the S3 default MAXTRANSFERSIZE of 10 MiB.

    .EXAMPLE
        PS C:\> Test-DbaBackupStorageCompatibility -SqlInstance sql2022 -Database Sales -MaxTransferSize 20971520

        Evaluates the Sales database using a 20 MiB MAXTRANSFERSIZE estimate. A backup written with this value requires compression.

    .EXAMPLE
        PS C:\> Test-DbaBackupStorageCompatibility -SqlInstance sql2022 -Threshold 80 -Monitor

        Returns only databases at or above 80 percent of the S3 part limit or outside an S3 limit, and signals when any are found.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [ValidateSet("S3")]
        [string]$Type = "S3",
        [ValidateRange(5242880, 20971520)]
        [long]$MaxTransferSize = 10485760,
        [ValidateRange(1, 100)]
        [int]$Threshold = 90,
        [switch]$Monitor,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $splatConnect = @{
                    SqlInstance    = $instance
                    SqlCredential  = $SqlCredential
                    MinimumVersion = 16
                }
                $server = Connect-DbaInstance @splatConnect
            } catch {
                $splatStopConnection = @{
                    Message     = "Failure"
                    Category    = "ConnectionError"
                    ErrorRecord = $PSItem
                    Target      = $instance
                    Continue    = $true
                }
                Stop-Function @splatStopConnection
            }

            $databases = @($server.Databases | Where-Object IsAccessible)
            if ($Database) {
                $databases = @($databases | Where-Object Name -In $Database)
            }
            if ($ExcludeDatabase) {
                $databases = @($databases | Where-Object Name -NotIn $ExcludeDatabase)
            }

            $monitorProblemCount = 0
            foreach ($db in $databases) {
                $splatBackupHistory = @{
                    SqlInstance     = $server
                    Database        = $db.Name
                    LastFull        = $true
                    EnableException = $EnableException
                }
                $lastBackup = Get-DbaDbBackupHistory @splatBackupHistory
                if (-not $lastBackup) {
                    Write-Message -Level Verbose -Message "No full backup history found for database $($db.Name)."
                    continue
                }

                $backupFileCount = @($lastBackup.Path | Where-Object { $null -ne $PSItem }).Count
                if ($backupFileCount -eq 0) {
                    Write-Message -Level Warning -Message "The most recent full backup for database $($db.Name) does not contain backup file paths and cannot be evaluated."
                    continue
                }

                if ($lastBackup.TotalSize.PSObject.Properties["Byte"]) {
                    $backupSizeBytes = [decimal]$lastBackup.TotalSize.Byte
                } else {
                    $backupSizeBytes = [decimal]$lastBackup.TotalSize
                }
                if ($lastBackup.CompressedBackupSize.PSObject.Properties["Byte"]) {
                    $compressedBackupSizeBytes = [decimal]$lastBackup.CompressedBackupSize.Byte
                } else {
                    $compressedBackupSizeBytes = [decimal]$lastBackup.CompressedBackupSize
                }
                if ($compressedBackupSizeBytes -gt 0) {
                    $effectiveBackupSizeBytes = $compressedBackupSizeBytes
                } else {
                    $effectiveBackupSizeBytes = $backupSizeBytes
                }

                $estimatedPartsPerFile = [long][Math]::Ceiling($effectiveBackupSizeBytes / $backupFileCount / $MaxTransferSize)
                $percentOfLimit = [Math]::Round(($estimatedPartsPerFile / [decimal]10000) * 100, 2)
                $partLimitExceeded = $estimatedPartsPerFile -gt 10000
                $fileLimitExceeded = $backupFileCount -gt 64
                $isCompatible = -not ($partLimitExceeded -or $fileLimitExceeded)

                if ($partLimitExceeded -and $fileLimitExceeded) {
                    $status = "ExceedsLimits"
                } elseif ($partLimitExceeded) {
                    $status = "ExceedsPartLimit"
                } elseif ($fileLimitExceeded) {
                    $status = "ExceedsFileLimit"
                } elseif ($percentOfLimit -ge $Threshold) {
                    $status = "Warning"
                } else {
                    $status = "Compatible"
                }

                $recommendedFileCount = $null
                $recommendedMaxTransferSize = $null
                $recommendation = $null
                if ($fileLimitExceeded) {
                    $recommendedFileCount = 64
                    $recommendation = "S3-compatible backups support at most 64 URLs. Reduce the backup file count and recalculate the estimated parts per file."
                }
                if ($partLimitExceeded) {
                    $requiredFiles = [int][Math]::Ceiling($effectiveBackupSizeBytes / ([decimal]10000 * $MaxTransferSize))
                    if ($requiredFiles -le 64) {
                        $recommendedFileCount = $requiredFiles
                        $recommendation = "Use at least $requiredFiles S3 URLs at the current MAXTRANSFERSIZE."
                    } elseif ($MaxTransferSize -lt 20971520) {
                        $requiredFilesAtMaximum = [int][Math]::Ceiling($effectiveBackupSizeBytes / ([decimal]10000 * 20971520))
                        if ($requiredFilesAtMaximum -le 64) {
                            $recommendedFileCount = $requiredFilesAtMaximum
                            $recommendedMaxTransferSize = 20971520
                            $recommendation = "Use MAXTRANSFERSIZE 20971520 with backup compression and at least $requiredFilesAtMaximum S3 URLs."
                        } else {
                            $recommendation = "The current effective backup size exceeds the S3 multipart limit even at 20 MiB and 64 URLs. Reduce backup size with compression or change the backup design."
                        }
                    } else {
                        $recommendation = "The current effective backup size exceeds the S3 multipart limit at the selected MAXTRANSFERSIZE. Reduce backup size with compression or change the backup design."
                    }
                } elseif ($status -eq "Warning") {
                    $recommendation = "The estimate is approaching the 10,000-part limit. Monitor backup growth or increase the file count before moving this backup to S3-compatible storage."
                }

                $result = [PSCustomObject]@{
                    ComputerName                    = $server.ComputerName
                    InstanceName                    = $server.ServiceName
                    SqlInstance                     = $server.DomainInstanceName
                    Database                        = $db.Name
                    Type                            = $Type
                    LastFullBackup                  = $lastBackup.Start
                    BackupSizeBytes                 = $backupSizeBytes
                    CompressedBackupSizeBytes       = $compressedBackupSizeBytes
                    EffectiveBackupSizeBytes        = $effectiveBackupSizeBytes
                    BackupFileCount                 = $backupFileCount
                    MaxTransferSize                 = $MaxTransferSize
                    EstimatedPartsPerFile           = $estimatedPartsPerFile
                    PercentOfLimit                  = $percentOfLimit
                    IsCompatible                    = $isCompatible
                    Status                          = $status
                    RecommendedFileCount            = $recommendedFileCount
                    RecommendedMaxTransferSizeBytes = $recommendedMaxTransferSize
                    Recommendation                  = $recommendation
                }

                if ($Monitor) {
                    if ($status -ne "Compatible") {
                        $monitorProblemCount++
                        $result
                    }
                } else {
                    $result
                }
            }

            if ($Monitor -and $monitorProblemCount -gt 0) {
                $splatStop = @{
                    Message         = "S3 backup storage compatibility risks found for $monitorProblemCount database(s)."
                    Category        = "InvalidResult"
                    EnableException = $EnableException
                }
                Stop-Function @splatStop
            }
        }
    }
}

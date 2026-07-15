function Get-DbaS3BackupStorageEstimate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [decimal]$EffectiveBackupSizeBytes,
        [Parameter(Mandatory)]
        [int]$BackupFileCount,
        [Parameter(Mandatory)]
        [long]$MaxTransferSize,
        [Parameter(Mandatory)]
        [int]$Threshold
    )

    $estimatedPartsPerFile = [long][Math]::Ceiling($EffectiveBackupSizeBytes / $BackupFileCount / $MaxTransferSize)
    $percentOfLimit = [Math]::Round(($estimatedPartsPerFile / [decimal]10000) * 100, 2)
    $partLimitExceeded = $estimatedPartsPerFile -gt 10000
    $fileLimitExceeded = $BackupFileCount -gt 64
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
        $requiredFiles = [int][Math]::Ceiling($EffectiveBackupSizeBytes / ([decimal]10000 * $MaxTransferSize))
        if ($requiredFiles -le 64) {
            $recommendedFileCount = $requiredFiles
            $recommendation = "Use at least $requiredFiles S3 URLs at the current MAXTRANSFERSIZE."
        } elseif ($MaxTransferSize -lt 20971520) {
            $requiredFilesAtMaximum = [int][Math]::Ceiling($EffectiveBackupSizeBytes / ([decimal]10000 * 20971520))
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

    [PSCustomObject]@{
        EstimatedPartsPerFile           = $estimatedPartsPerFile
        PercentOfLimit                  = $percentOfLimit
        IsCompatible                    = $isCompatible
        Status                          = $status
        RecommendedFileCount            = $recommendedFileCount
        RecommendedMaxTransferSizeBytes = $recommendedMaxTransferSize
        Recommendation                  = $recommendation
    }
}

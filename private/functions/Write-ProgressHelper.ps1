function Write-ProgressHelper {
    # thanks adam!
    # https://www.adamtheautomator.com/building-progress-bar-powershell-scripts/
    param (
        [int]$StepNumber,
        [string]$Activity,
        [string]$Message,
        [int]$TotalSteps,
        [Alias("NoProgress")]
        [switch]$ExcludePercent,
        [int]$Id,
        [int]$ParentId = -1,
        [switch]$Completed
    )

    $caller = (Get-PSCallStack)[1].Command

    if (-not $Activity) {
        $Activity = switch ($caller) {
            "Export-DbaInstance" {
                "Performing instance export for $instance"
            }
            "Start-DbaMigration" {
                "Performing instance migration"
            }
            "Install-DbaSqlWatch" {
                "Installing SQLWatch"
            }
            "Invoke-DbaDbLogShipRecovery" {
                "Performing log shipping recovery"
            }
            "Invoke-DbaDbMirroring" {
                "Setting up mirroring"
            }
            "New-DbaAvailabilityGroup" {
                "Adding new availability group"
            }
            "Sync-DbaAvailabilityGroup" {
                "Syncing availability group"
            }
            default {
                "Executing $caller"
            }
        }
    }

    # The host identifies a bar by its Id, not by its Activity text, so the completion must carry the Id of the bar it ends
    $splatProgress = @{
        Id       = $Id
        ParentId = $ParentId
        Activity = $Activity
    }
    # Write-Progress refuses an empty Status and shows its own default text without one
    if ($Message) {
        $splatProgress.Status = $Message
    }

    if ($Completed) {
        Write-Progress -Id $Id -Activity $Activity -Completed
    } elseif ($ExcludePercent) {
        Write-Progress @splatProgress
    } else {
        if (-not $TotalSteps -and $caller -ne "<ScriptBlock>") {
            if (-not $script:progressHelperTotalSteps) {
                $script:progressHelperTotalSteps = @{ }
            }
            if (-not $script:progressHelperTotalSteps.ContainsKey($caller)) {
                # Count only the calls that report a step, not the ones that complete the bar or show no percentage
                $callerCommand = Get-Command -Module dbatools -Name $caller -ErrorAction SilentlyContinue
                $stepCalls = 0
                if ($callerCommand) {
                    $stepCalls = @($callerCommand.Definition -split "`n" | Where-Object { $PSItem -match "Write-ProgressHelper" -and $PSItem -notmatch "-Completed|-ExcludePercent|-NoProgress" }).Count
                }
                $script:progressHelperTotalSteps[$caller] = $stepCalls
            }
            $TotalSteps = $script:progressHelperTotalSteps[$caller]
        }
        if (-not $TotalSteps) {
            $percentComplete = 0
        } else {
            # Write-Progress refuses a percentage above 100, which a step counter that outruns its total would produce
            $percentComplete = [System.Math]::Min(100, [System.Math]::Max(0, [int](($StepNumber / $TotalSteps) * 100)))
        }
        Write-Progress @splatProgress -PercentComplete $percentComplete
    }
}

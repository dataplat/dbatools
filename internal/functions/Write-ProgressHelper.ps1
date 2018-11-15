function Write-ProgressHelper {
    # thanks adam!
    # https://www.adamtheautomator.com/building-progress-bar-powershell-scripts/
    param (
        [int]$StepNumber,
        [string]$Activity,
        [string]$Message
    )

    $caller = (Get-PSCallStack)[1].Command

    if (-not $Activity) {
        $Activity = switch ($caller) {
            "Export-DbaInstance" {
                "Performing Instance Export for $instance"
            }
            "Install-DbaSqlWatch" {
                "Installing SQLWatch"
            }
            "Invoke-DbaDbLogShipRecovery" {
                "Performing log shipping recovery"
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
                "Processing $caller"
            }
        }
    }

    $TotalSteps = ([regex]::Matches((Get-Command -Module dbatools -Name $caller).Definition, "Write-ProgressHelper")).Count
    Write-Progress -Activity $Activity -Status $Message -PercentComplete (($StepNumber / $TotalSteps) * 100)
}
function Write-ProgressHelper {
    # thanks adam!
    # https://www.adamtheautomator.com/building-progress-bar-powershell-scripts/
    param (
        [int]$StepNumber,
        [string]$Activity,
        [string]$Message,
        [int]$TotalSteps = 3
    )
    Write-Progress -Activity $Activity -Status $Message -PercentComplete (($StepNumber / $TotalSteps) * 100)
}


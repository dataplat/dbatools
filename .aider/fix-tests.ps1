param (
    [int]$First = 1000,
    [int]$Skip = 0
)
$testerrors = Get-Content /workspace/.aider/prompts/fix-errors.json | ConvertFrom-Json

$promptTemplate = Get-Content /workspace/.aider/prompts/fix-template.md
$commands = $testerrors | Select-Object -First $First -Skip $Skip
$added = @()

foreach ($command in $commands) {
    $cmdName = $command.Command
    $filename = "/workspace/tests/$cmdName.Tests.ps1"
    Write-Host "Processing $cmdName"

    if (-not (Test-Path $filename)) {
        Write-Warning "No tests found for $cmdName"
        Write-Warning "$filename not found"
        continue
    }

    $cmdPrompt = $promptTemplate -replace "--CMDNAME--", $cmdName

    # Run Aider in non-interactive mode with auto-confirmation
    if ($added -notcontains $cmdName) {
        $added += $cmdName
        aider --message "$cmdPrompt" --file $filename --sonnet --no-stream --cache-prompts --read /workspace/.aider/prompts/conventions.md /workspace/.aider/prompts/types.md /workspace/.aider/prompts/errors.md
    } else {
        aider --message "$cmdPrompt" --sonnet --no-stream --cache-prompts --read /workspace/.aider/prompts/conventions.md /workspace/.aider/prompts/types.md
    }
}
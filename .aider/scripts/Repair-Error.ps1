param (
    [int]$First = 1000,
    [int]$Skip = 0
)

$promptTemplate = Get-Content /workspace/.aider/prompts/fix-errors.md

$testerrors = Get-Content /workspace/.aider/prompts/errors.json | ConvertFrom-Json
$commands = $testerrors | Select-Object -ExpandProperty Command -Unique | Sort-Object

foreach ($command in $commands) {
    $filename = "/workspace/tests/$command.Tests.ps1"
    Write-Output "Processing $command"

    if (-not (Test-Path $filename)) {
        Write-Warning "No tests found for $command"
        Write-Warning "$filename not found"
        continue
    }

    $cmdPrompt = $promptTemplate -replace "--CMDNAME--", $command

    $testerr = $testerrors | Where-Object Command -eq $command
    foreach ($err in $testerr) {
        $cmdPrompt += "`n`n"
        $cmdPrompt += "Error: $($err.ErrorMessage)`n"
        $cmdPrompt += "Line: $($err.LineNumber)`n"
    }

    # Run Aider in non-interactive mode with auto-confirmation
    aider --message "$cmdPrompt" --file $filename --sonnet --no-stream --cache-prompts --read /workspace/tests/constants.ps1
}
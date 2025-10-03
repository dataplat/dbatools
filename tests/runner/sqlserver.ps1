# Load GitHub Actions helpers
. "$PSScriptRoot\github-helpers.ps1"

Write-Host -Object "Creating migration & backup directories" -ForegroundColor DarkGreen
New-Item -Path C:\temp -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
New-Item -Path C:\temp\migration -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
New-Item -Path C:\temp\backups -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
New-Item -Path C:\github\dbatools\.git -ItemType Directory -ErrorAction SilentlyContinue | Out-Null

if ($env:SCENARIO) {

    Write-Host -Object "Scenario $($env:scenario)" -ForegroundColor DarkGreen

    #Write-Host -Object "Main instance $($env:MAIN_INSTANCE)" -ForegroundColor DarkGreen
    #Write-Host -Object "Setup scripts $($env:SETUP_SCRIPTS)" -ForegroundColor DarkGreen
    $Setup_Scripts = $env:SETUP_SCRIPTS.split(',').Trim()
    foreach ($Setup_Script in $Setup_Scripts) {
        $SetupScriptPath = Join-Path $env:GITHUB_WORKSPACE $Setup_Script
        Add-GitHubTest -Name $Setup_Script -Framework NUnit -FileName $Setup_Script -Outcome Running
        $sw = [system.diagnostics.stopwatch]::startNew()
        . $SetupScriptPath
        $sw.Stop()
        Update-GitHubTest -Name $Setup_Script -Framework NUnit -FileName $Setup_Script -Outcome Passed -Duration $sw.ElapsedMilliseconds
    }
}

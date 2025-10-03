# Load GitHub Actions helpers
. "$PSScriptRoot\github-helpers.ps1"

Add-GitHubTest -Name "runner.post" -Framework NUnit -FileName "runner.post.ps1" -Outcome Running
$sw = [system.diagnostics.stopwatch]::startNew()
Write-Host -Object "runner.post: Sending coverage data" -ForeGroundColor DarkGreen
$ProjectRoot = $env:GITHUB_WORKSPACE
$ModuleBase = $ProjectRoot
$pester5CoverageFiles = Get-ChildItem -Path "$ModuleBase\Pester5Coverage*.xml"
foreach ($coverageFile in $pester5CoverageFiles) {
    Write-Host -Object "runner.post: Sending $($coverageFile.FullName)" -ForeGroundColor DarkGreen
    Push-GitHubArtifact $coverageFile.FullName -FileName $coverageFile.Name
    codecov -f $coverageFile.FullName --flag "pester5_$($env:SCENARIO.ToLowerInvariant())" | Out-Null
}

$sw.Stop()
Update-GitHubTest -Name "runner.post" -Framework NUnit -FileName "runner.post.ps1" -Outcome Passed -Duration $sw.ElapsedMilliseconds

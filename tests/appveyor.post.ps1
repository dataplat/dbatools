Add-AppveyorTest -Name "appveyor.post" -Framework NUnit -FileName "appveyor.post.ps1" -Outcome Running
$sw = [system.diagnostics.stopwatch]::startNew()
Write-Host -Object "appveyor.post: Sending coverage data" -ForeGroundColor DarkGreen
$ProjectRoot = $env:APPVEYOR_BUILD_FOLDER
$ModuleBase = $ProjectRoot
$pesterCoverageFiles = Get-ChildItem -Path "$ModuleBase\PesterCoverage*.xml"
foreach ($coverageFile in $pesterCoverageFiles) {
    Write-Host -Object "appveyor.post: Sending $($coverageFile.FullName)" -ForeGroundColor DarkGreen
    Push-AppveyorArtifact $coverageFile.FullName -FileName $coverageFile.Name
    # The flag still says pester5 on purpose. codecov keys its history off the flag name, so
    # renaming it starts a new series and loses the trend on the existing dashboards.
    codecov -f $coverageFile.FullName --flag "pester5_$($env:SCENARIO.ToLowerInvariant())" | Out-Null
}

$sw.Stop()
Update-AppveyorTest -Name "appveyor.post" -Framework NUnit -FileName "appveyor.post.ps1" -Outcome Passed -Duration $sw.ElapsedMilliseconds
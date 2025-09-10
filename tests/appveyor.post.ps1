Add-AppveyorTest -Name "appveyor.post" -Framework NUnit -FileName "appveyor.post.ps1" -Outcome Running
$sw = [system.diagnostics.stopwatch]::startNew()
Write-Host -Object "appveyor.post: Sending coverage data" -ForeGroundColor DarkGreen
$ProjectRoot = $env:APPVEYOR_BUILD_FOLDER
$ModuleBase = $ProjectRoot
$pester5CoverageFiles = Get-ChildItem -Path "$ModuleBase\Pester5Coverage*.xml"
foreach ($coverageFile in $pester5CoverageFiles) {
    Write-Host -Object "appveyor.post: Sending $($coverageFile.FullName)" -ForeGroundColor DarkGreen
    Push-AppveyorArtifact $coverageFile.FullName -FileName $coverageFile.Name
    codecov -f $coverageFile.FullName --flag "pester5_$($env:SCENARIO.ToLowerInvariant())" | Out-Null
}

$sw.Stop()
Update-AppveyorTest -Name "appveyor.post" -Framework NUnit -FileName "appveyor.post.ps1" -Outcome Passed -Duration $sw.ElapsedMilliseconds
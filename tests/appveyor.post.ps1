Add-AppveyorTest -Name "appveyor.post" -Framework NUnit -FileName "appveyor.post.ps1" -Outcome Running
$sw = [system.diagnostics.stopwatch]::startNew()
Write-Host -Object "appveyor.post: Sending coverage data" -ForeGroundColor DarkGreen
Push-AppveyorArtifact PesterResultsCoverage.json -FileName "PesterResultsCoverage"
codecov -f PesterResultsCoverage.json --flag "ps,$($env:SCENARIO.ToLowerInvariant())" | Out-Null
$sw.Stop()
Update-AppveyorTest -Name "appveyor.post" -Framework NUnit -FileName "appveyor.post.ps1" -Outcome Passed -Duration $sw.ElapsedMilliseconds
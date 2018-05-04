Add-AppveyorTest -Name "appveyor.post" -Framework NUnit -FileName "appveyor.post.ps1" -Outcome Running
$sw = [system.diagnostics.stopwatch]::startNew()
Write-Host -Object "appveyor.post: Sending coverage data" -ForeGroundColor DarkGreen
Push-AppveyorArtifact PesterResultsCoverage.json -FileName "PesterResultsCoverage"
codecov -f PesterResultsCoverage.json --flag "ps,$($env:SCENARIO.toLower())" | Out-Null
# DLL unittests only in default scenario
if($env:SCENARIO -eq 'default') {
  Write-Host -Object "appveyor.post: DLL unittests"  -ForeGroundColor DarkGreen
  OpenCover.Console.exe `
    -register:user `
    -target:"vstest.console.exe" `
    -targetargs:"/logger:Appveyor bin\projects\dbatools\dbatools.Tests\bin\Debug\dbatools.Tests.dll" `
    -output:"coverage.xml" `
    -filter:"+[dbatools]*" `
    -returntargetcode
  Push-AppveyorArtifact coverage.xml -FileName "OpenCover C# Report"
  codecov -f "coverage.xml" --flag "dll,$($env:SCENARIO.toLower())" | Out-Null
}
$sw.Stop()
Update-AppveyorTest -Name "appveyor.post" -Framework NUnit -FileName "appveyor.post.ps1" -Outcome Passed -Duration $sw.ElapsedMilliseconds
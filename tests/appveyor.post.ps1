Write-Host -Object "appveyor.post: Sending coverage data" -ForeGroundColor DarkGreen
Push-AppveyorArtifact PesterResultsCoverage.json -FileName "PesterResultsCoverage"
codecov -f PesterResultsCoverage.json --flag "ps,$($env:SCENARIO.toLower())" | Out-Null
# DLL unittests only in default scenario
if($env:SCENARIO -eq 'default') {
  Write-Host -Object "appveyor.post: DLL unittests"  -ForeGroundColor DarkGreen
  choco install opencover.portable | Out-Null
  OpenCover.Console.exe `
    -register:user `
    -target:"vstest.console.exe" `
    -targetargs:"/logger:Appveyor bin\projects\dbatools\dbatools.Tests\bin\Debug\dbatools.Tests.dll" `
    -output:"coverage.xml" `
    -filter:"+[dbatools]*" `
    -returntargetcode | Out-Null
  Push-AppveyorArtifact coverage.xml -FileName "OpenCover c# report"
  codecov -f "coverage.xml" --flag "dll,$($env:SCENARIO.toLower())" | Out-Null
}

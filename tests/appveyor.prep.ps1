Add-AppveyorTest -Name "appveyor.prep" -Framework NUnit -FileName "appveyor.prep.ps1" -Outcome Running
$sw = [system.diagnostics.stopwatch]::startNew()
Write-Host -Object "appveyor.prep: Cloning lab materials"  -ForegroundColor DarkGreen
git clone -q --branch=master --depth=1 https://github.com/sqlcollaborative/appveyor-lab.git C:\github\appveyor-lab

#Get codecov (to upload coverage results)
Write-Host -Object "appveyor.prep: Install codecov" -ForegroundColor DarkGreen
choco install codecov | Out-Null

#Write-Host -Object "appveyor.prep: Install Nuget" -ForegroundColor DarkGreen
## appveyor has 2.8.5.208 installed, so no need to nuget over and over just to fetch scriptanalyzer
#Install-PackageProvider Nuget –Force | Out-Null

#Get PSScriptAnalyzer (to check warnings)
Write-Host -Object "appveyor.prep: Install PSScriptAnalyzer" -ForegroundColor DarkGreen
Install-Module -Name PSScriptAnalyzer | Out-Null

#Get Pester (to run tests)
Write-Host -Object "appveyor.prep: Install Pester" -ForegroundColor DarkGreen
choco install pester | Out-Null

#Get opencover.portable (to run DLL tests)
Write-Host -Object "appveyor.prep: Install opencover.portable" -ForegroundColor DarkGreen
choco install opencover.portable | Out-Null

$sw.Stop()
Update-AppveyorTest -Name "appveyor.prep" -Framework NUnit -FileName "appveyor.prep.ps1" -Outcome Passed -Duration $sw.ElapsedMilliseconds


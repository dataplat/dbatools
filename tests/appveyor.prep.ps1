Add-AppveyorTest -Name "appveyor.prep" -Framework NUnit -FileName "appveyor.prep.ps1" -Outcome Running
$sw = [system.diagnostics.stopwatch]::startNew()
Write-Host -Object "appveyor.prep: Cloning lab materials"  -ForegroundColor DarkGreen
git clone -q --branch=master --depth=1 https://github.com/sqlcollaborative/appveyor-lab.git C:\github\appveyor-lab

#Get codecov (to upload coverage results)
Write-Host -Object "appveyor.prep: Install codecov" -ForegroundColor DarkGreen
choco install codecov | Out-Null

#Get PSScriptAnalyzer (to check warnings)
Write-Host -Object "appveyor.prep: Install PSScriptAnalyzer" -ForegroundColor DarkGreen
if (-not(Test-Path 'C:\Program Files\WindowsPowerShell\Modules\PSScriptAnalyzer\1.17.1')) {
    Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck | Out-Null
}

#Get Pester (to run tests) - choco isn't working onall scenarios, weird
Write-Host -Object "appveyor.prep: Install Pester" -ForegroundColor DarkGreen
if (-not(Test-Path 'C:\Program Files\WindowsPowerShell\Modules\Pester\4.4.2')) {
    Install-Module -Name Pester -Force -SkipPublisherCheck | Out-Null
}


#Get opencover.portable (to run DLL tests)
Write-Host -Object "appveyor.prep: Install opencover.portable" -ForegroundColor DarkGreen
choco install opencover.portable | Out-Null

$sw.Stop()
Update-AppveyorTest -Name "appveyor.prep" -Framework NUnit -FileName "appveyor.prep.ps1" -Outcome Passed -Duration $sw.ElapsedMilliseconds
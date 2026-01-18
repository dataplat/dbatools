Add-AppveyorTest -Name "appveyor.prep" -Framework NUnit -FileName "appveyor.prep.ps1" -Outcome Running

# Invoke appveyor.common.ps1 to know which tests to run
. "$($env:APPVEYOR_BUILD_FOLDER)\tests\appveyor.common.ps1"
$AllScenarioTests = Get-TestsForBuildScenario -ModuleBase $env:APPVEYOR_BUILD_FOLDER -Silent

if ($AllScenarioTests.Count -eq 0) {
    #Exit early without provisioning if no tests to run
    Write-Host -Object "appveyor.prep: exit early without provisioning (no tests to run)"  -ForegroundColor DarkGreen
    Exit-AppveyorBuild
    return
}


$sw = [system.diagnostics.stopwatch]::startNew()
Write-Host -Object "appveyor.prep: Cloning lab materials"  -ForegroundColor DarkGreen
git clone -q --branch=master --depth=1 https://github.com/dataplat/appveyor-lab.git C:\github\appveyor-lab

#Get codecov (to upload coverage results)
Write-Host -Object "appveyor.prep: Install codecov" -ForegroundColor DarkGreen
choco install codecov | Out-Null
#FIXME : read about the new uploader https://docs.codecov.com/docs/codecov-uploader#using-the-uploader

#Get PSScriptAnalyzer (to check warnings)
Write-Host -Object "appveyor.prep: Install PSScriptAnalyzer" -ForegroundColor DarkGreen
Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck -MaximumVersion 1.18.2

#Get dbatools.library
Write-Host -Object "appveyor.prep: Install dbatools.library" -ForegroundColor DarkGreen
# Use centralized version management for dbatools.library installation
& "$PSScriptRoot\..\.github\scripts\install-dbatools-library.ps1"
# Validate that the correct version was installed
$expectedVersion = (Get-Content '.github/dbatools-library-version.json' | ConvertFrom-Json).version
$installedModule = Get-Module dbatools.library -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1

if (-not $installedModule) {
    throw "dbatools.library module was not installed successfully"
}

Write-Host -Object "appveyor.prep: Expected version: $expectedVersion" -ForegroundColor Green
Write-Host -Object "appveyor.prep: Installed version: $($installedModule.Version)" -ForegroundColor Green

# Verify the version matches (allowing for version format differences)
if ($installedModule.Version.ToString() -notmatch [regex]::Escape($expectedVersion.Split('-')[0])) {
    Write-Warning "Installed version $($installedModule.Version) may not match expected version $expectedVersion"
} else {
    Write-Host -Object "appveyor.prep: Version validation successful" -ForegroundColor Green
}

# Get Pester (to run tests)
Write-Host -Object "appveyor.prep: Install Pester5" -ForegroundColor DarkGreen
Install-Module -Name Pester -Force -SkipPublisherCheck -RequiredVersion 5.7.1

# Setup DbatoolsConfig Path.DbatoolsExport path
Write-Host -Object "appveyor.prep: Create Path.DbatoolsExport" -ForegroundColor DarkGreen
$null = New-Item -Path C:\Users\appveyor\Documents\DbatoolsExport -ItemType Directory

Write-Host -Object "appveyor.prep: Creating temp directory" -ForegroundColor DarkGreen
$null = New-Item -Path C:\Temp -ItemType Directory

Write-Host -Object "appveyor.prep: Configuring WSMan (see #9782)" -ForegroundColor DarkGreen
$null = Set-WSManQuickConfig -Force

Write-Host -Object "appveyor.prep: Trust SQL Server Cert (now required)" -ForegroundColor DarkGreen
Import-Module dbatools.library
Import-Module C:\github\dbatools\dbatools.psd1
Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register
Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false -Register
$sw.Stop()
Update-AppveyorTest -Name "appveyor.prep" -Framework NUnit -FileName "appveyor.prep.ps1" -Outcome Passed -Duration $sw.ElapsedMilliseconds
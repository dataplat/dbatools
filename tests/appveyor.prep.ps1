Write-Host -Object "appveyor.prep: Cloning lab materials"  -ForegroundColor DarkGreen
git clone -q --branch=master --depth=1 https://github.com/sqlcollaborative/appveyor-lab.git C:\github\appveyor-lab
#Install codecov to upload results
Write-Host -Object "appveyor.prep: Install codecov" -ForegroundColor DarkGreen
choco install codecov | Out-Null

Write-Host -Object "appveyor.prep: Install PSScriptAnalyzer" -ForegroundColor DarkGreen
Install-PackageProvider Nuget –Force | Out-Null
Install-Module -Name PSScriptAnalyzer | Out-Null


# "Get Pester manually"
Write-Host -Object "appveyor.prep: Install Pester" -ForegroundColor DarkGreen
Install-Module -Name Pester -Repository PSGallery -Force | Out-Null
Write-Host -Object "appveyor.prep: Cloning lab materials"  -ForegroundColor DarkGreen
git clone -q --branch=master --depth=1 https://github.com/sqlcollaborative/appveyor-lab.git C:\github\appveyor-lab
#Install codecov to upload results
Write-Host -Object "appveyor.prep: Install codecov" -ForegroundColor DarkGreen
choco install codecov | Out-Null
# "Installing nuget and PSScriptAnalyzer"
#Install-PackageProvider NuGet -MinimumVersion '2.8.5.201' -Force | Out-Null
#Import-PackageProvider NuGet -MinimumVersion '2.8.5.201' -Force | Out-Null
#Install-Module -Name PSScriptAnalyzer -RequiredVersion 1.6.0 -Repository PSGallery -Force | Out-Null

# "Get Pester manually"
Write-Host -Object "appveyor.prep: Install Pester" -ForegroundColor DarkGreen
Install-Module -Name Pester -Repository PSGallery -Force | Out-Null
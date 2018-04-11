<#
Write-Host "Current Path : $((Get-Location).Path)"

Write-Host @"
# Listing local variables #
#-------------------------#

"@

Get-Variable | Format-Table Name, @{
    n   = "Type"; e = {
        if ($_.Value -eq $null) { "<Null>" }
        else { $_.Value.GetType().FullName }
    }
}, Value | Out-String | Out-Host

Write-Host @"

# Listing environment variables #
#-------------------------------#

"@

Get-ChildItem "env:" | Out-Host

Write-Host @"

# Listing arguments #
#-------------------#

"@

$args | Format-List | Out-Host

Write-Host "########################################################################################################" -ForegroundColor DarkGreen
#>

$previousVersion = Import-Clixml ".\vsts-version.xml"
$currentVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo((Get-Item "bin\dbatools.dll").FullName).FileVersion
Remove-Item ".\vsts-version.xml"

if ($previousVersion -ne $currentVersion)
{
    $branch = $env:BUILD_SOURCEBRANCHNAME
    Write-Host "Previous: $previousVersion | Current: $currentVersion | Library should be updated"

    git add .
    git commit -m "VSTS Library Compile ***NO_CI***"
    $errorMessage = git push "https://$env:SYSTEM_ACCESSTOKEN@github.com/sqlcollaborative/dbatools.git" head:$branch 2>&1
    if ($LASTEXITCODE -gt 0) { throw $errorMessage }
}
else
{
    Write-Host "Version: $currentVersion | Library is up to date"
}
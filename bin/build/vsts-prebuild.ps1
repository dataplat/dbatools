$item = Get-Item "bin\dbatools.dll"
$version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($item.FullName).FileVersion
$version | Export-Clixml ".\vsts-version.xml"
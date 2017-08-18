[CmdletBinding()]
param (
	[string]$Path,
	[switch]$Beta
)

try {
	Update-Module dbatools -Erroraction Stop
	Write-Output "Updated using the PowerShell Gallery"
	return
}
catch {
	Write-Output "dbatools was not installed by the PowerShell Gallery, continuing with web install."
}

$module = Import-Module -Name dbatools -ErrorAction SilentlyContinue -Force
$localpath = $module.ModuleBase

if ($null -eq $localpath) {
	$localpath = "$HOME\Documents\WindowsPowerShell\Modules\dbatools"
}
else {
	Write-Output "Updating current install"
}

try {
	if (-not $path) {
		if ($PSCommandPath.Length -gt 0) {
			$path = Split-Path $PSCommandPath
			if ($path -match "github") {
				Write-Output "Looks like this installer is run from your GitHub Repo, defaulting to psmodulepath"
				$path = $localpath
			}
		}
		else {
			$path = $localpath
		}
	}
}
catch {
	$path = $localpath
}

if (-not $path -or (Test-Path -Path "$path\.git")) {
	$path = $localpath
}

Write-Output "Installing module to $path"

Remove-Module -Name dbatools -ErrorAction SilentlyContinue

if ($beta) {
	$url = 'https://dbatools.io/devzip'
	$branch = "development"
}
else {
	$url = 'https://dbatools.io/zip'
	$branch = "master"
}

$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
$zipfile = "$temp\dbatools.zip"

if (!(Test-Path -Path $path)) {
	try {
		Write-Output "Creating directory: $path"
		New-Item -Path $path -ItemType Directory | Out-Null
	}
	catch {
		throw "Can't create $Path. You may need to Run as Administrator"
	}
}
else {
	try {
		Write-Output "Deleting previously installed module"
		Remove-Item -Path "$path\*" -Force -Recurse
	}
	catch {
		throw "Can't delete $Path. You may need to Run as Administrator"
	}
}

Write-Output "Downloading archive from github"
try {
	Invoke-WebRequest $url -OutFile $zipfile
}
catch {
	#try with default proxy and usersettings
	Write-Output "Probably using a proxy for internet access, trying default proxy settings"
	(New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
	Invoke-WebRequest $url -OutFile $zipfile
}

# Unblock if there's a block
Unblock-File $zipfile -ErrorAction SilentlyContinue

Write-Output "Unzipping"

# Keep it backwards compatible
$shell = New-Object -ComObject Shell.Application
$zipPackage = $shell.NameSpace($zipfile)
$destinationFolder = $shell.NameSpace($temp)
$destinationFolder.CopyHere($zipPackage.Items())

Write-Output "Cleaning up"
Move-Item -Path "$temp\dbatools-$branch\*" $path
Remove-Item -Path "$temp\dbatools-$branch"
Remove-Item -Path $zipfile

Write-Output "Done! Please report any bugs to dbatools.io/issues or clemaire@gmail.com."
if ((Get-Command -Module dbatools).count -eq 0) { Import-Module "$path\dbatools.psd1" -Force }
Get-Command -Module dbatools
Write-Output "`n`nIf you experience any function missing errors after update, please restart PowerShell or reload your profile."

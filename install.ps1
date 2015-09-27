Remove-Module dbatools -ErrorAction SilentlyContinue
$url = 'https://github.com/ctrlbold/dbatools/archive/master.zip'
$path = Join-Path -Path (Split-Path -Path $profile) -ChildPath '\Modules\dbatools'
$zipfile = "$($pwd.path)\sqltools.zip"


if (!(Test-Path -Path $path)){
	Write-Output "Creating directory: $path"
	New-Item -Path $path -ItemType Directory | Out-Null 
} else { 
	Write-Output "Deleting previously installed module"
	Remove-Item -Path "$path\*" -Force -Recurse 
}

Write-Output "Downloading archive from github"
Invoke-WebRequest $url -OutFile $zipfile

Write-Output "Unzipping"
# Keep it backwards compatible
$shell = New-Object -COM Shell.Application
$zipPackage = $shell.NameSpace($zipfile)
$destinationFolder = $shell.NameSpace($($pwd.path))
$destinationFolder.CopyHere($zipPackage.Items())

Write-Output "Cleaning up"
Move-Item -Path "$($pwd.path)\dbatools-master\*" $path
Remove-Item -Path "$($pwd.path)\dbatools-master"
Remove-Item -Path $zipfile


Write-Output "Done! Please report any bugs to clemaire@gmail.com."
Get-Command -Module dbatools
Write-Output "`n`nIf you experience any function missing errors after update, please restart PowerShell or reload your profile."
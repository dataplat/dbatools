$url = 'https://github.com/ctrlbold/dbatools/archive/master.zip'
$path = Join-Path -Path (Split-Path -Path $profile) -ChildPath '\Modules\dbatools'
$zipfile = "$env:temp\sqltools.zip"


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
$destinationFolder = $shell.NameSpace($env:temp)
$destinationFolder.CopyHere($zipPackage.Items())

Write-Output "Cleaning up"
Move-Item -Path "$env:temp\dbatools-master\*" $path
Remove-Item -Path "$env:temp\dbatools-master"
Remove-Item -Path $zipfile

#Remove-Module dbatools -ErrorAction SilentlyContinue
#Import-Module "$path\dbatools.psd1"

Write-Output "Done! Please report any bugs to clemaire@gmail.com."
Get-Command -Module dbatools
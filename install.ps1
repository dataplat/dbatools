[CmdletBinding()]
param (
    [string]$Path,
    [switch]$Beta
)

function Write-LocalMessage {
    [CmdletBinding()]
    param (
        [string]$Message
    )

    if (Test-Path function:Write-Message) { Write-Message -Level Output -Message $Message }
    else { Write-Host $Message }
}

try {
    if (Get-InstalledModule dbatools -Erroraction Stop) {
        Update-Module dbatools -Erroraction Stop
        Write-LocalMessage -Message "Updated using the PowerShell Gallery"
        return
    }
} catch {
    Write-LocalMessage -Message "dbatools was not installed by the PowerShell Gallery, continuing with web install."
}

$currentVersionTls = [Net.ServicePointManager]::SecurityProtocol
$currentSupportableTls = [Math]::Max($currentVersionTls.value__, [Net.SecurityProtocolType]::Tls.value__)
$availableTls = [enum]::GetValues('Net.SecurityProtocolType') | Where-Object {
    $_ -gt $currentSupportableTls
}
$availableTls | ForEach-Object {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor $_
}

$dbatools_copydllmode = $true

foreach ($modpath in $($env:PSModulePath -split [IO.Path]::PathSeparator)) {
    #Grab the user's default home directory module path for later
    if ($modpath -like "*$([Environment]::UserName)*") {
        $userpath = $modpath
    }
    try {
        $temppath = Join-Path -Path $modpath -ChildPath "dbatools"
        $localpath = (Get-ChildItem $temppath -ErrorAction Stop).FullName
    } catch {
        $localpath = $null
    }
}

if ($null -eq $localpath) {
    # In case dbatools is not currently installed in any PSModulePath put it in the $userpath
    if (Test-Path -Path $userpath) {
        $localpath = Join-Path -Path $userpath -ChildPath "dbatools"
    }
} else {
    Write-LocalMessage -Message "Updating current install"
}

try {
    if (-not $path) {
        if ($PSCommandPath.Length -gt 0) {
            $path = Split-Path $PSCommandPath
            if ($path -match "github") {
                Write-LocalMessage -Message "Looks like this installer is run from your GitHub Repo, defaulting to psmodulepath"
                $path = $localpath
            }
        } else {
            $path = $localpath
        }
    }
} catch {
    $path = $localpath
}

if (-not $path -or (Test-Path -Path "$path\.git")) {
    $path = $localpath
}

If ($lib = [appdomain]::CurrentDomain.GetAssemblies() | Where-Object FullName -like "dbatools, *") {
    $wildcardpath = Join-Path -Path $Path -ChildPath *
    if ($lib.Location -like "$wildcardpath") {
        Write-LocalMessage @"
We have detected dbatools to be already imported from
$path
In a manner that prevents us from updating it, since dll files have been locked.
In order to ensure a valid update, please:
- Close all consoles that have dbatools imported (Remove-Module dbatools is NOT enough)
- Start a new PowerShell console
- Run '`$dbatools_copydllmode = `$true' (without the single-quotes)
- Import dbatools and run Update-Dbatools
If done in this order, the binaries will be copied to another location before import, allowing for a save update.
"@
        return
    }
}

Write-LocalMessage -Message "Installing module to $path"

if (!(Test-Path -Path $path)) {
    try {
        Write-LocalMessage -Message "Creating directory: $path"
        New-Item -Path $path -ItemType Directory | Out-Null
    } catch {
        throw "Can't create $Path. You may need to Run as Administrator: $_"
    }
}

if ($beta) {
    $url = 'https://dbatools.io/devzip'
    $branch = "development"
} else {
    $url = 'https://dbatools.io/zip'
    $branch = "master"
}

$temp = ([System.IO.Path]::GetTempPath())
$zipfile = Join-Path -Path $temp -ChildPath "dbatools.zip"

Write-LocalMessage -Message "Downloading archive from github"
try {
    (New-Object System.Net.WebClient).DownloadFile($url, $zipfile)
} catch {
    try {
        #try with default proxy and usersettings
        Write-LocalMessage -Message "Probably using a proxy for internet access, trying default proxy settings"
        $wc = (New-Object System.Net.WebClient)
        $wc.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        $wc.DownloadFile($url, $zipfile)
    } catch {
        Write-Warning "Error downloading file :( $_"
        return
    }
}

# Unblock if there's a block
if (($PSVersionTable.PSVersion.Major -lt 6) -or ($PSVersionTable.Platform -and $PSVersionTable.Platform -eq 'Win32NT')) {
    Write-LocalMessage -Message "Unblocking"
    Unblock-File $zipfile -ErrorAction SilentlyContinue
}

Write-LocalMessage -Message "Unzipping"


$branchpath = Join-Path -Path $temp -ChildPath "dbatools-$branch"
$oldpath = Join-Path -Path $temp -ChildPath "dbatools-old"
$wildcardoldpath = Join-Path -Path $oldpath -ChildPath *
$wildcardbranchpath = Join-Path -Path $branchpath -ChildPath *

Remove-Item -ErrorAction SilentlyContinue $branchpath -Recurse -Force
Remove-Item -ErrorAction SilentlyContinue $oldpath -Recurse -Force
$null = New-Item $oldpath -ItemType Directory
if (($PSVersionTable.Keys -contains "Platform") -and $psversiontable.Platform -ne "Win32NT") {
    $destinationFolder = $temp
    Expand-Archive -Path $zipfile -DestinationPath $destinationFolder -Force
} else {
    # Keep it backwards compatible
    $shell = New-Object -ComObject Shell.Application
    $zipPackage = $shell.NameSpace($zipfile)
    $destinationFolder = $shell.NameSpace($temp)
    $destinationFolder.CopyHere($zipPackage.Items())
}

Write-LocalMessage -Message "Applying Update"
Write-LocalMessage -Message "1) Backing up previous installation"
Copy-Item -Path $wildcardpath -Destination $oldpath -ErrorAction Stop
try {
    Write-LocalMessage -Message "2) Cleaning up installation directory"
    Remove-Item $wildcardpath -Recurse -Force -ErrorAction Stop
} catch {
    Write-LocalMessage -Message @"
Failed to clean up installation directory, rolling back update.
This usually has one of two causes:
- Insufficient privileges (need to run as admin)
- A file is locked - generally a dll file from having the module imported in some process.

You can run the following line before importing dbatools to prevent file locking:
`$dbatools_copydllmode = `$true
But it increases the time needed to import the module, so we only recommend using it for updates.

Exception:
$_
"@
    Copy-Item -Path $wildcardoldpath -Destination $path -ErrorAction Ignore -Recurse
    Remove-Item $oldpath -Recurse -Force
    return
}
Write-LocalMessage -Message "3) Setting up current version"
Move-Item -Path $wildcardbranchpath -Destination $path -ErrorAction SilentlyContinue -Force
Remove-Item -Path $branchpath -Recurse -Force
Remove-Item $oldpath -Recurse -Force
Remove-Item -Path $zipfile -Recurse -Force

Write-LocalMessage -Message "Done! Please report any bugs to dbatools.io/issues"
if (Get-Module dbatools) {
    Write-LocalMessage -Message @"

Please restart PowerShell before working with dbatools.
"@
} else {
    $psd1 = Join-Path -Path $path -ChildPath "dbatools.psd1"
    Import-Module $psd1 -Force
    Write-LocalMessage @"

dbatools v $((Get-Module dbatools).Version)
# Commands available: $((Get-Command -Module dbatools -CommandType Function | Measure-Object).Count)

"@
}
[Net.ServicePointManager]::SecurityProtocol = $currentVersionTls
Write-LocalMessage -Message "`n`nIf you experience any function missing errors after update, please restart PowerShell or reload your profile."
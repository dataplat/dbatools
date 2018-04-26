[CmdletBinding()]
param(
    [string] $ProjectPath = "$psscriptroot\projects\dbatools\dbatools.sln",
    [ValidateSet('ps3', 'ps4', 'Release', 'Debug')]
    [string] $MsbuildConfiguration,
    [Parameter(HelpMessage='Target to run instead of build')]
    [string] $MsbuildTarget = 'Build'
)

if ([string]::IsNullOrEmpty($MsbuildConfiguration)) {
    $MsbuildConfiguration = switch ($PSVersionTable.PSVersion.Major) {
        3 { "ps3" }
        4 { "ps4" }
        default { "Release" }
    }
}

function Get-MsBuildPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    process{
        $system = [Appdomain]::CurrentDomain.GetAssemblies() | Where-Object FullName -like "System, *"
        $frameworkFolder = "Framework$(if ([intptr]::Size -eq 8) { "64" })"
        $rawPath = "$(Split-Path $system.Location)\..\..\..\..\$($frameworkFolder)\$($system.ImageRuntimeVersion)\msbuild.exe"
        (Resolve-Path $rawPath).Path
    }
}

$start = Get-Date
$msbuild = Get-MsBuildPath

if (-not (Test-Path $msbuild)) {
    throw "msbuild not found, cannot compile library! Check your .NET installation health, then try again. Path checked: $msbuild"
}

$msbuildOptions = ""
if ($env:APPVEYOR -eq 'True') {
    $msbuildOptions = '/logger:"C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll"'
    $msbuildConfiguration = 'Debug'

    if (-not (Test-Path "C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll")) {
        throw "msbuild logger not found, cannot compile library! Check your .NET installation health, then try again. Path checked: $msbuild"
    }
}

if ( -not (Test-Path $ProjectPath)) {
    throw new-object 'System.IO.FileNotFoundException' 'Could not file project or solution', $ProjectPath
}

Write-Verbose -Message "Building the library with command $msbuild $ProjectPath /p:Configuration=$msbuildConfiguration $msbuildOptions /t:$MsBuildTarget"
& $msbuild $ProjectPath "/p:Configuration=$msbuildConfiguration" $msbuildOptions "/t:$MsBuildTarget"

if ($MsbuildTarget -eq 'Build') {
    try {
        Write-Verbose -Message "Found library, trying to copy & import"
        if ($script:alwaysBuildLibrary) { Move-Item -Path "$PSScriptRoot\dbatools.dll" -Destination $script:DllRoot -Force -ErrorAction Stop }
        else { Copy-Item -Path "$PSScriptRoot\dbatools.dll" -Destination $script:DllRoot -Force -ErrorAction Stop }
        Add-Type -Path "$script:DllRoot\dbatools.dll" -ErrorAction Stop
    }
    catch {
        Write-Verbose -Message "Failed to copy & import, attempting to import straight from the module directory"
        Add-Type -Path "$PSScriptRoot\dbatools.dll" -ErrorAction Stop
    }
    Write-Verbose -Message "Total duration: $((Get-Date) - $start)"
}
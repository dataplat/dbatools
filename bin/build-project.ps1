[CmdletBinding()]
param (
    [string]$ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSModuleRoot -ChildPath 'bin\projects\dbatools\dbatools.sln')),
    [ValidateSet('ps3', 'ps4', 'Release', 'Debug')]
    [string]$MsbuildConfiguration = "Release",
    [string]$MsbuildOptions = "",
    [Parameter(HelpMessage = 'Target to run instead of build')]
    [string]$MsbuildTarget = 'Build'
)

if (-not $PSBoundParameters.ContainsKey('MsbuildConfiguration')) {
    $_MsbuildConfiguration = switch ($PSVersionTable.PSVersion.Major) {
        3 {
            "ps3"
        }
        4 {
            "ps4"
        }
        default {
            "Release"
        }
    }
} else {
    $_MsbuildConfiguration = $MsbuildConfiguration
}

function Get-MsBuildPath {
    [CmdletBinding()]
    [OutputType([string])]
    param ()
    process {
        $rawPath = "$(Split-Path ([string].Assembly.Location))\msbuild.exe"
        (Resolve-Path $rawPath).Path
    }
}

$start = Get-Date
$msbuild = Get-MsBuildPath

if (-not (Test-Path $msbuild)) {
    throw "msbuild not found, cannot compile library! Check your .NET installation health, then try again. Path checked: $msbuild"
}

if ($env:APPVEYOR -eq 'True') {
    $MsbuildOptions = $MsbuildOptions + '/logger:"C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll" '
    $_MsbuildConfiguration = 'Debug'
    
    if (-not (Test-Path "C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll")) {
        throw "msbuild logger not found, cannot compile library! Check your .NET installation health, then try again. Path checked: $msbuild"
    }
}

#$MsbuildOptions = $MsbuildOptions + '/logger:BinaryLogger,"{0}";"{1}" ' -f (Join-Path $PSScriptRoot 'StructuredLogger.dll'), (Resolve-Path '..\msbuild.bin.log').Path

if (-not (Test-Path $ProjectPath)) {
    throw new-object 'System.IO.FileNotFoundException' 'Could not file project or solution', $ProjectPath
}

Write-Verbose -Message "Building the library with command $msbuild $ProjectPath /p:Configuration=$_MsbuildConfiguration $MsbuildOptions /t:$MsBuildTarget"
& $msbuild $ProjectPath "/p:Configuration=$_MsbuildConfiguration" $MsbuildOptions "/t:$MsBuildTarget"

if ($MsbuildTarget -eq 'Build') {
    try {
        Write-Verbose -Message "Found library, trying to copy & import"
        if ($script:alwaysBuildLibrary) {
            Move-Item -Path (Resolve-Path -Path "$PSModuleRoot\bin\dbatools.dll") -Destination $script:DllRoot -Force -ErrorAction Stop
        } else {
            Copy-Item -Path (Resolve-Path -Path "$PSModuleRoot\bin\dbatools.dll") -Destination $script:DllRoot -Force -ErrorAction Stop
        }
        Add-Type -Path (Resolve-Path -Path "$PSModuleRoot\dbatools.dll") -ErrorAction Stop
    } catch {
        Write-Verbose -Message "Failed to copy & import, attempting to import straight from the module directory"
        Add-Type -Path (Resolve-Path -Path "$PSModuleRoot\bin\dbatools.dll") -ErrorAction Stop
    }
    Write-Verbose -Message "Total duration: $((Get-Date) - $start)"
}
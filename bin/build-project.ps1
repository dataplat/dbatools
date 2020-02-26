[CmdletBinding()]
param (
    [string]$ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSModuleRoot -ChildPath 'bin\projects\dbatools\dbatools.sln')),
    [ValidateSet('ps3', 'ps4', 'Release', 'Debug')]
    [string]$MsbuildConfiguration = "Release",
    [Parameter(HelpMessage = 'Target to run instead of build')]
    [string]$MsbuildTarget = 'Build',
    [string]$DllRoot = $script:DllRoot,
    [string]$LibraryBase = (Join-Path $PSModuleRoot "bin")
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

function Get-DotNetPath {
    [CmdletBinding()]
    [OutputType([string])]
    param ()
    process {
        if (Get-Command dotnet.exe -CommandType Application -ErrorAction SilentlyContinue) { return (Get-Command dotnet.exe -CommandType Application | Select-Object -First 1).Source }
        "$([System.Environment]::GetFolderPath("ProgramFiles"))\dotnet\dotnet.exe" | Select-Object -First 1
    }
}

$start = Get-Date
$dotnet = Get-DotNetPath

if (-not (Test-Path $dotnet)) {
    throw "dotnet application not found, cannot compile library! Download and install the dotnet SDK from https://dotnet.microsoft.com/download"
}

if ($env:APPVEYOR -eq 'True') {
    $_MsbuildConfiguration = 'Debug'
}

if (-not (Test-Path $ProjectPath)) {
    throw new-object 'System.IO.FileNotFoundException' 'Could not file project or solution', $ProjectPath
}

Write-Verbose -Message "Building the library with command $dotnet build $ProjectPath -c $_MsbuildConfiguration"
& $dotnet build $ProjectPath -c $_MsbuildConfiguration

if ($MsbuildTarget -eq 'Build') {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $dll = (Resolve-Path -Path "$libraryBase\netcoreapp2.1\dbatools.dll" -ErrorAction Ignore)
    } else {
        $dll = (Resolve-Path -Path "$libraryBase\net452\dbatools.dll" -ErrorAction Ignore)
    }
    try {
        Write-Verbose -Message "Found library, trying to copy & import"
        if ($script:alwaysBuildLibrary) {
            Move-Item -Path $dll -Destination $DllRoot -Force -ErrorAction Stop
        } else {
            Copy-Item -Path $dll -Destination $DllRoot -Force -ErrorAction Stop
        }
        Add-Type -Path (Resolve-Path -Path "$DllRoot\dbatools.dll") -ErrorAction Stop
    } catch {
        Write-Verbose -Message "Failed to copy & import, attempting to import straight from the module directory"
        Add-Type -Path $dll -ErrorAction Stop
    }
    Write-Verbose -Message "Total duration: $((Get-Date) - $start)"
}
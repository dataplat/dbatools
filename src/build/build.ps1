param(
    [switch]$BuildZip,
    [switch]$CoreOnly
)
$PSDefaultParameterValues["*:Force"] = $true
$PSDefaultParameterValues["*:Confirm"] = $false
$ProgressPreference = "SilentlyContinue"
# Import MSI waiting functions
. "$PSScriptRoot\Wait-MsiInstall.ps1"
. "$PSScriptRoot\Copy-LockedArtifact.ps1"

# Get script root and project root
$scriptroot = $PSScriptRoot
if (-not $scriptroot) {
    $scriptroot = Split-Path -Path $MyInvocation.MyCommand.Path
}
$root = Split-Path -Path $scriptroot
Push-Location $root

# Create centralized build directory
$artifactsDir = Join-Path $root "artifacts"
$dbatoolsLibraryDir = Join-Path $artifactsDir "library"
$libPath = $dbatoolsLibraryDir
$tempPath = Join-Path $artifactsDir "temp"
$publishDir = Join-Path $artifactsDir "publish"
$licensePath = Join-Path $dbatoolsLibraryDir "third-party-licenses"

function Test-StagedDllWritable {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    try {
        $stream = [System.IO.File]::Open($Path, "Open", "ReadWrite", "None")
        $stream.Close()
        return $true
    } catch {
        return $false
    }
}

function Get-StagedDllHolder {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
        try {
            $loaded = @($proc.Modules | Where-Object { $_.FileName -eq $Path })
            if ($loaded.Count -eq 0) {
                continue
            }
            $started = "unknown"
            try {
                if ($proc.StartTime) {
                    $started = $proc.StartTime
                }
            } catch {
                # Keep the holder when its start time cannot be read.
            }
        } catch {
            # The lock check already proved that this file is unavailable; attribution is best effort.
            continue
        }
        [PSCustomObject]@{
            Id      = $proc.Id
            Name    = $proc.ProcessName
            Started = $started
        }
    }
}

# Clean up previous build artifacts
if (Test-Path $artifactsDir) {
    $lockedDlls = @(Get-ChildItem -Path $dbatoolsLibraryDir -Filter "*.dll" -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { -not (Test-StagedDllWritable -Path $_.FullName) })
    if ($lockedDlls.Count -gt 0) {
        Write-Host "ERROR: refusing to clean retained artifacts because DLLs are held by live processes:" -ForegroundColor Red
        foreach ($lockedDll in $lockedDlls) {
            Write-Host "  $($lockedDll.FullName)" -ForegroundColor Red
            $holders = @(Get-StagedDllHolder -Path $lockedDll.FullName)
            if ($holders.Count -eq 0) {
                Write-Host "    no holder could be attributed - it is likely held under another user account." -ForegroundColor Red
                continue
            }
            foreach ($holder in $holders) {
                Write-Host "    $($holder.Name) pid=$($holder.Id) started=$($holder.Started)" -ForegroundColor Red
            }
        }
        exit 1
    }
    Remove-Item -Path $artifactsDir -Recurse -ErrorAction SilentlyContinue
}

# Create build directory structure
$null = New-Item -ItemType Directory -Path $artifactsDir -Force
$null = New-Item -ItemType Directory -Path $dbatoolsLibraryDir -Force
$null = New-Item -ItemType Directory -Path $tempPath -Force
$null = New-Item -ItemType Directory -Path $publishDir -Force

# Keep the module root diagnosable if a later build step fails.
Copy-LockedArtifact -Source (Join-Path $root "loader/Import-DbatoolsLibrary.ps1") -Destination (Join-Path $dbatoolsLibraryDir "Import-DbatoolsLibrary.ps1")
Copy-LockedArtifact -Source (Join-Path $root "loader/CoreRedirector.cs") -Destination (Join-Path $dbatoolsLibraryDir "CoreRedirector.cs")
Write-Host "Copied loader files to artifacts/library" -ForegroundColor Green

Write-Host "Created centralized build directory at: $artifactsDir" -ForegroundColor Cyan
Write-Host "All build artifacts will be placed in this directory to keep the root clean." -ForegroundColor Yellow
Push-Location "$root\project"

dotnet clean

# Create temp directories for publish output
$tempDesktopPublish = Join-Path $publishDir "desktop-temp"
$tempCorePublish = Join-Path $publishDir "core-temp"
$null = New-Item -ItemType Directory -Path $tempDesktopPublish -Force
$null = New-Item -ItemType Directory -Path $tempCorePublish -Force

Write-Host "Created publish directories at: $publishDir" -ForegroundColor Cyan

# Publish .NET Framework (desktop) to temp directory first
Write-Host "Publishing .NET Framework build..."
dotnet publish dbatools/dbatools.csproj --configuration release --framework net472 --output $tempDesktopPublish --nologo --self-contained true | Out-String -OutVariable build
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: dotnet publish (net472) failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

# Copy desktop publish output preserving structure
Write-Host "Copying .NET Framework output with preserved structure..."
$null = New-Item -ItemType Directory -Path (Join-Path $libPath "desktop/lib") -Force
Copy-LockedArtifactTree -Source $tempDesktopPublish -Destination (Join-Path $libPath "desktop/lib")


# Verify and patch desktop publish output
Write-Host "Verifying desktop publish..."

# Publish .NET 8 (core) to temp directory first
Write-Host "Publishing .NET 8 build..."
dotnet publish dbatools/dbatools.csproj --configuration release --framework net8.0 --output $tempCorePublish --nologo --self-contained true | Out-String -OutVariable build
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: dotnet publish (net8.0) failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

# Copy core publish output preserving structure
Write-Host "Copying .NET 8 output with preserved structure..."
$null = New-Item -ItemType Directory -Path (Join-Path $libPath "core/lib") -Force
Copy-LockedArtifactTree -Source $tempCorePublish -Destination (Join-Path $libPath "core/lib")

# Verify and organize runtime dependencies
Write-Host "Verifying .NET 8 runtime dependencies..."
$coreRuntimesPath = Join-Path $libPath "core\lib\runtimes"
$desktopRuntimesPath = Join-Path $libPath "desktop\lib\runtimes"

# Ensure desktop runtimes directory exists
New-Item -ItemType Directory -Path $desktopRuntimesPath -Force | Out-Null

if (Test-Path $coreRuntimesPath) {
    Write-Host "Core runtimes folder found. Processing native dependencies..." -ForegroundColor Green

    $architectures = @("win-x86", "win-x64", "win-arm", "win-arm64")

    foreach ($arch in $architectures) {
        $coreArchPath = Join-Path $coreRuntimesPath "$arch\native"
        $desktopArchPath = Join-Path $desktopRuntimesPath "$arch\native"

        if (Test-Path $coreArchPath) {
            Write-Host "Processing architecture: $arch" -ForegroundColor Cyan

            # Ensure desktop architecture directory exists
            New-Item -ItemType Directory -Path $desktopArchPath -Force | Out-Null

            # Copy all native files from core to desktop for Windows PowerShell compatibility
            Get-ChildItem -Path $coreArchPath -File | ForEach-Object {
                $sourcePath = $_.FullName
                $destPath = Join-Path $desktopArchPath $_.Name

                Copy-LockedArtifact -Source $sourcePath -Destination $destPath
                Write-Host "  Copied: $($_.Name)" -ForegroundColor Green
            }

            # Verify SNI DLL specifically
            $sniPath = Join-Path $coreArchPath "Microsoft.Data.SqlClient.SNI.dll"
            if (Test-Path $sniPath) {
                $dllInfo = Get-Item $sniPath
                Write-Host "  SNI DLL verified - Size: $($dllInfo.Length) bytes" -ForegroundColor Green
            } else {
                Write-Warning "  SNI DLL not found for $arch"
            }
        } else {
            Write-Warning "Architecture path not found: $coreArchPath"
        }
    }
} else {
    Write-Host "ERROR: Core runtimes folder not found at: $coreRuntimesPath" -ForegroundColor Red

    # Check what's actually in the core lib directory
    $coreLibPath = Join-Path $libPath "core\lib"
    if (Test-Path $coreLibPath) {
        Write-Host "Core lib directory contents:" -ForegroundColor Yellow
        Get-ChildItem -Path $coreLibPath -Recurse | Where-Object { $_.Name -like "*SNI*" } | Select-Object FullName
    }
}

# Build and stage satellite cmdlet assemblies (migration/specs/modules.md section 5.2):
# one dll per module, both editions, into artifacts/modules/dbatools.<module>/{desktop,core}/.
# These dlls ship INSIDE each satellite's folder; the shared dbatools.dll and its SMO/SqlClient
# dependency tree ship once, in the dbatools module's library folder.
# NOTE: -Filter "dbatools.*" ALSO matches the extensionless "dbatools" runtime directory
# (FindFirstFile-compatible wildcard semantics), so the runtime project must be excluded by
# name - it publishes through artifacts/lib, never as a satellite. Uncaught until 2026-07-06:
# stale project/dbatools/bin copies masked the mis-staging until a solution restore cleaned
# them and the loop died on the copy.
$satelliteProjects = Get-ChildItem -Path . -Directory -Filter "dbatools.*" | Where-Object {
    $_.Name -ne "dbatools" -and $_.Name -ne "dbatools.Tests" -and (Test-Path (Join-Path $_.FullName "$($_.Name).csproj"))
}
foreach ($satellite in $satelliteProjects) {
    $satelliteName = $satellite.Name
    Write-Host "Building satellite cmdlet assembly: $satelliteName"
    dotnet build "$satelliteName/$satelliteName.csproj" --configuration release --nologo | Out-String -OutVariable satelliteBuild
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: satellite build ($satelliteName) failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    $moduleStage = Join-Path $artifactsDir "modules/$satelliteName"
    $null = New-Item -ItemType Directory -Path (Join-Path $moduleStage "desktop") -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $moduleStage "core") -Force
    Copy-LockedArtifact -Source "$satelliteName/bin/release/net472/$satelliteName.dll" -Destination (Join-Path $moduleStage "desktop/$satelliteName.dll")
    Copy-LockedArtifact -Source "$satelliteName/bin/release/net8.0/$satelliteName.dll" -Destination (Join-Path $moduleStage "core/$satelliteName.dll")
    # dll-Help.xml (MAML) is generated only from the net8.0 build (CmdletHelp.props) but is
    # target-framework independent - the same cmdlets carry the same help on both editions - so
    # the one file is staged beside the assembly in BOTH desktop and core.
    $helpFile = "$satelliteName/bin/release/net8.0/$satelliteName.dll-Help.xml"
    if (Test-Path $helpFile) {
        Copy-LockedArtifact -Source $helpFile -Destination (Join-Path $moduleStage "desktop/$satelliteName.dll-Help.xml")
        Copy-LockedArtifact -Source $helpFile -Destination (Join-Path $moduleStage "core/$satelliteName.dll-Help.xml")
        Write-Host "Staged satellite: $satelliteName (desktop + core + help)" -ForegroundColor Green
    } else {
        Write-Host "WARNING: no dll-Help.xml generated for $satelliteName" -ForegroundColor Yellow
        Write-Host "Staged satellite: $satelliteName (desktop + core)" -ForegroundColor Green
    }
}

if ($CoreOnly) {
    Write-Host "CoreOnly specified - returning after core build"
    return
}
# Run tests specifically for dbatools.Tests
# dotnet test dbatools.Tests/dbatools.Tests.csproj --framework net472 --verbosity normal --no-restore --nologo | Out-String -OutVariable test
Pop-Location

$targetDesktop = (Join-Path $libPath "desktop/net472")
if (Test-Path $targetDesktop) {
    Remove-Item -Path $targetDesktop -Recurse -ErrorAction SilentlyContinue
}
$targetCore = (Join-Path $libPath "core/net8.0")
if (Test-Path $targetCore) {
    Remove-Item -Path $targetCore -Recurse -ErrorAction SilentlyContinue
}

$tempdir = Join-Path ([System.IO.Path]::GetTempPath()) "dbatools-build"

# Create all required directories
$null = New-Item -ItemType Directory $tempdir -Force -ErrorAction Ignore
$null = New-Item -ItemType Directory (Join-Path $libPath "desktop/third-party/bogus") -Force
$null = New-Item -ItemType Directory (Join-Path $libPath "core/third-party/bogus") -Force
$null = New-Item -ItemType Directory (Join-Path $libPath "core/lib/runtimes") -Force
$null = New-Item -ItemType Directory (Join-Path $tempPath "bogus") -Force
$null = New-Item -ItemType Directory (Join-Path $tempdir "nuget") -Force

Register-PackageSource -provider NuGet -name nugetRepository -Location https://www.nuget.org/api/v2 -Trusted -ErrorAction Ignore

# Download all required packages
Invoke-WebRequest -Uri https://www.nuget.org/api/v2/package/Bogus -OutFile (Join-Path $tempPath "bogus.zip")

$ProgressPreference = "Continue"

# Extract all packages
# A NuGet package is an ordinary zip archive, so extracting it needs no external tool. Shelling out
# to 7z made the build depend on a program that is absent from a clean machine, and it failed late
# and quietly: the run aborted here yet still reported a success exit code, leaving a drop with no
# module manifest in it.
#
# This unpacks via the .NET API rather than Expand-Archive deliberately. The "*:Confirm" entry in
# $PSDefaultParameterValues at the top of this script is injected into the cmdlets Expand-Archive
# calls internally, which makes it throw "Object reference not set to an instance of an object" and
# extract nothing. A .NET call cannot be reached by parameter defaults, so it is stable no matter
# what this script sets. Do not "simplify" this back to Expand-Archive without removing that default.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$bogusArchive = Join-Path $tempPath "bogus.zip"
$bogusStage = Join-Path $tempPath "bogus"
# Both steps must fail the build loudly. A .NET method that throws while the error preference is
# "Continue" writes an error record and then carries straight on to the next statement, so an
# unguarded failure here yields a drop that is missing Bogus and still reports success - the exact
# silent-partial-output problem that replacing the external extractor was meant to end.
try {
    # ExtractToDirectory refuses to overwrite an existing file, so start from a clean directory.
    if (Test-Path -LiteralPath $bogusStage) {
        Remove-Item -LiteralPath $bogusStage -Recurse -Force -ErrorAction Stop
    }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($bogusArchive, $bogusStage)
} catch {
    throw "Failed to extract $bogusArchive to $bogusStage. $($_.Exception.Message)"
}


# Copy Bogus files for both frameworks
Write-Host "Copying Bogus.dll..." -ForegroundColor Green

# Copy Bogus.dll for .NET Framework (handle case sensitivity)
# A missing Bogus here is fatal, not a warning: this code only runs on a full build (-CoreOnly
# returns earlier), so the package is always expected to carry it. Warning and carrying on produced
# a drop with no Bogus.dll in it and still exited 0, which reads as a successful build.
if (Test-Path (Join-Path $tempPath "bogus/lib/net40/bogus.dll")) {
    Copy-LockedArtifact -Source (Join-Path $tempPath "bogus/lib/net40/bogus.dll") -Destination (Join-Path $libPath "desktop/third-party/bogus/Bogus.dll")
} elseif (Test-Path (Join-Path $tempPath "bogus/lib/net40/Bogus.dll")) {
    Copy-LockedArtifact -Source (Join-Path $tempPath "bogus/lib/net40/Bogus.dll") -Destination (Join-Path $libPath "desktop/third-party/bogus/Bogus.dll")
} else {
    throw "Bogus.dll for .NET Framework (net40) not found under $(Join-Path $tempPath "bogus/lib/net40"). The extracted package layout is not what this build expects."
}

# Copy Bogus.dll for .NET Core (handle case sensitivity)
$bogusCoreCopied = $false
# Try net6.0 first (both lowercase and uppercase)
if (Test-Path (Join-Path $tempPath "bogus/lib/net6.0/bogus.dll")) {
    Copy-LockedArtifact -Source (Join-Path $tempPath "bogus/lib/net6.0/bogus.dll") -Destination (Join-Path $libPath "core/third-party/bogus/Bogus.dll")
    $bogusCoreCopied = $true
} elseif (Test-Path (Join-Path $tempPath "bogus/lib/net6.0/Bogus.dll")) {
    Copy-LockedArtifact -Source (Join-Path $tempPath "bogus/lib/net6.0/Bogus.dll") -Destination (Join-Path $libPath "core/third-party/bogus/Bogus.dll")
    $bogusCoreCopied = $true
} elseif (Test-Path (Join-Path $tempPath "bogus/lib/netstandard2.0/bogus.dll")) {
    Copy-LockedArtifact -Source (Join-Path $tempPath "bogus/lib/netstandard2.0/bogus.dll") -Destination (Join-Path $libPath "core/third-party/bogus/Bogus.dll")
    $bogusCoreCopied = $true
} elseif (Test-Path (Join-Path $tempPath "bogus/lib/netstandard2.0/Bogus.dll")) {
    Copy-LockedArtifact -Source (Join-Path $tempPath "bogus/lib/netstandard2.0/Bogus.dll") -Destination (Join-Path $libPath "core/third-party/bogus/Bogus.dll")
    $bogusCoreCopied = $true
}

# Fatal for the same reason as the .NET Framework copy above.
if (-not $bogusCoreCopied) {
    throw "Bogus.dll for .NET Core not found under $(Join-Path $tempPath "bogus/lib") in any of the expected framework folders. The extracted package layout is not what this build expects."
}

# Core files are already in place from dotnet publish

# Copy var/misc files to appropriate locations
Write-Host "Copying additional assemblies from var/misc..."
# Copy files that go to both core and desktop
Get-ChildItem "./var/misc/both" -Filter "*.dll" | ForEach-Object {
    Copy-LockedArtifact -Source $_.FullName -Destination (Join-Path $libPath "core/lib/$($_.Name)")
    Copy-LockedArtifact -Source $_.FullName -Destination (Join-Path $libPath "desktop/lib/$($_.Name)")
}

# Copy desktop-specific files. System.Runtime.CompilerServices.Unsafe 4.0.4.1 from var/misc/desktop is left out of
# desktop/lib: the net472 publish already placed the .NET Framework build of Unsafe 6.x there (the version restore
# resolves for SqlClient, System.Memory and Microsoft.Identity.Client), and Microsoft Entra sign-ins through
# Microsoft.Identity.Client need members that 4.x lacks. The loader serves that 6.x copy to SMO's 4.0.4.1 requests too.
Get-ChildItem "./var/misc/desktop" -Filter "*.dll" | Where-Object Name -ne "System.Runtime.CompilerServices.Unsafe.dll" | ForEach-Object { Copy-LockedArtifact -Source $_.FullName -Destination (Join-Path $libPath "desktop/lib/$($_.Name)") }
$desktopUnsafe = Join-Path $libPath "desktop/lib/System.Runtime.CompilerServices.Unsafe.dll"
if (-not (Test-Path $desktopUnsafe)) {
    throw "System.Runtime.CompilerServices.Unsafe.dll is missing from the .NET Framework publish output at $desktopUnsafe."
}
$desktopUnsafeVersion = [System.Reflection.AssemblyName]::GetAssemblyName((Resolve-Path $desktopUnsafe).Path).Version
if ($desktopUnsafeVersion.Major -lt 6) {
    throw "System.Runtime.CompilerServices.Unsafe in desktop/lib is version $desktopUnsafeVersion; Microsoft Entra sign-ins on Windows PowerShell need 6.x."
}
Write-Host "Desktop System.Runtime.CompilerServices.Unsafe is version $desktopUnsafeVersion"

# Cleanup temporary files and artifacts
Write-Host "Cleaning up temporary files..."
# We don't remove the artifacts directory since it's our centralized build output
Get-ChildItem -Path (Join-Path $libPath "*") -Recurse -Include "*.pdf","*.xml" | Remove-Item -Force

# Create directory structure for different versions of System.Runtime.CompilerServices.Unsafe.dll
$null = New-Item -ItemType Directory -Path (Join-Path $libPath "desktop/v4") -Force
$null = New-Item -ItemType Directory -Path (Join-Path $libPath "desktop/lib/v6") -Force

# Copy v4.0.4.1 version from var/misc/desktop to desktop/v4
Write-Host "Copying System.Runtime.CompilerServices.Unsafe v4.0.4.1 for SMO..."
Copy-LockedArtifact -Source "./var/misc/desktop/System.Runtime.CompilerServices.Unsafe.dll" -Destination (Join-Path $libPath "desktop/v4/System.Runtime.CompilerServices.Unsafe.dll")

# Copy v6.0.0.0 version from NuGet cache to core/lib. desktop/lib/v6 gets the .NET Framework build of 6.x that
# desktop/lib holds (a net6.0 build cannot load on .NET Framework).
Write-Host "Copying System.Runtime.CompilerServices.Unsafe v6.0.0.0 for SSAS..."
Copy-LockedArtifact -Source $desktopUnsafe -Destination (Join-Path $libPath "desktop/lib/v6/System.Runtime.CompilerServices.Unsafe.dll")
$nugetCache = "$env:USERPROFILE\.nuget\packages";
$v6Unsafe = Get-ChildItem -Path "$nugetCache\system.runtime.compilerservices.unsafe\*\lib\net6.0\System.Runtime.CompilerServices.Unsafe.dll" -Recurse | Select-Object -Last 1
if ($v6Unsafe) {
    Copy-LockedArtifact -Source $v6Unsafe.FullName -Destination (Join-Path $libPath "core/lib/System.Runtime.CompilerServices.Unsafe.dll")
} else {
    Write-Warning "Could not find System.Runtime.CompilerServices.Unsafe v6.0.0.0 in NuGet cache"
}

# Copy third-party-licenses
$licensePath = Join-Path $dbatoolsLibraryDir "third-party-licenses"
$null = New-Item -ItemType Directory -Path $licensePath -Force

if (Test-Path (Join-Path $root "var/third-party-licenses")) {
    Copy-LockedArtifactTree -Source (Join-Path $root "var/third-party-licenses") -Destination $licensePath
    Write-Host "Included third-party-licenses in artifacts/library" -ForegroundColor Green
} elseif (Test-Path (Join-Path $artifactsDir "third-party-licenses")) {
    Copy-LockedArtifactTree -Source (Join-Path $artifactsDir "third-party-licenses") -Destination $licensePath
    Write-Host "Included third-party-licenses from artifacts in artifacts/library" -ForegroundColor Green
}

# Create zip file for testing (release format)
Write-Host "Creating library.zip for testing..."
$zipPath = Join-Path $artifactsDir "library.zip"
if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
}

Write-Host "All build artifacts are centralized in: $artifactsDir" -ForegroundColor Green

# Create the zip file directly from the artifacts/library directory
Push-Location $artifactsDir
if ($BuildZip) {
    Compress-Archive -Path "library" -DestinationPath $zipPath -CompressionLevel Optimal -Force
}
Pop-Location

Write-Host "Created test zip: $zipPath"
Write-Host "Zip structure: library.zip contains the 'library' folder at root"
Write-Host "For testing: extract it into the dbatools module folder, so it becomes <module>\library"

# Final validation of critical files
Write-Host "`n=== Final Build Validation ===" -ForegroundColor Cyan
$validationErrors = @()

# Check for critical runtime dependencies
$criticalFiles = @(
    @{Path = "core\lib\runtimes\win-x64\native\Microsoft.Data.SqlClient.SNI.dll"; Description = ".NET Core SNI DLL (Windows x64)"},
    @{Path = "core\lib\runtimes\win\lib\net8.0\Microsoft.Data.SqlClient.dll"; Description = ".NET Core SqlClient (Windows runtime asset)"},
    @{Path = "core\lib\runtimes\unix\lib\net8.0\Microsoft.Data.SqlClient.dll"; Description = ".NET Core SqlClient (Unix runtime asset)"},
    @{Path = "core\lib\Microsoft.Data.SqlClient.dll"; Description = ".NET Core SqlClient"},
    @{Path = "desktop\lib\Microsoft.Data.SqlClient.dll"; Description = ".NET Framework SqlClient"},
    @{Path = "core\lib\dbatools.dll"; Description = ".NET Core dbatools assembly"},
    @{Path = "desktop\lib\dbatools.dll"; Description = ".NET Framework dbatools assembly"}
)

foreach ($file in $criticalFiles) {
    $fullPath = Join-Path $libPath $file.Path
    if (Test-Path $fullPath) {
        Write-Host "[OK] Found: $($file.Description)" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Missing: $($file.Description) at $($file.Path)" -ForegroundColor Red
        $validationErrors += "Missing: $($file.Description)"
    }
}

$coreSqlClientPath = Join-Path $libPath "core\lib\Microsoft.Data.SqlClient.dll"
$coreUnixSqlClientPath = Join-Path $libPath "core\lib\runtimes\unix\lib\net8.0\Microsoft.Data.SqlClient.dll"
if ((Test-Path $coreSqlClientPath) -and (Test-Path $coreUnixSqlClientPath)) {
    $coreSqlClientHash = (Get-FileHash -Path $coreSqlClientPath -Algorithm SHA256).Hash
    $coreUnixSqlClientHash = (Get-FileHash -Path $coreUnixSqlClientPath -Algorithm SHA256).Hash
    if ($coreSqlClientHash -eq $coreUnixSqlClientHash) {
        Write-Host "[ERROR] core\lib\Microsoft.Data.SqlClient.dll matches the Unix runtime asset" -ForegroundColor Red
        $validationErrors += "Core SqlClient was overwritten with the Unix runtime asset"
    } else {
        Write-Host "[OK] Core SqlClient root assembly was not overwritten with the Unix runtime asset" -ForegroundColor Green
    }
}

# Check if runtimes folder structure exists
if (Test-Path (Join-Path $libPath "core\lib\runtimes")) {
    Write-Host "[OK] Runtimes folder structure preserved" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Runtimes folder structure missing!" -ForegroundColor Red
    $validationErrors += "Runtimes folder structure missing"
}

if ($validationErrors.Count -eq 0) {
    Write-Host "`nBuild completed successfully. All critical files present." -ForegroundColor Green
} else {
    Write-Host "`nBuild completed with errors:" -ForegroundColor Red
    $validationErrors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

# if github actions and lastexitcode =0 then exit with success
if ($env:GITHUB_ACTIONS -and $LASTEXITCODE -eq 0) {
    exit 0
} else {
    exit $LASTEXITCODE
}

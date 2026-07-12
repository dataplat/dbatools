function Install-DbaParquet {
    <#
    .SYNOPSIS
        Installs Parquet.NET assemblies required by Import-DbaParquet.

    .DESCRIPTION
        Downloads Parquet.NET from NuGet and installs the netstandard2.0 assemblies into the dbatools data directory.
        The installer also downloads and extracts the managed dependency closure declared by the NuGet packages.

        Parquet.NET is a managed .NET library, so the installed assemblies work across Windows, Linux, and macOS as long
        as the host PowerShell/.NET runtime can load netstandard2.0 assemblies.

        By default, assemblies are installed to the dbatools data directory for the current user. Use -Path for a custom
        portable location, or -LocalFile to install from an already downloaded nupkg, zip, or folder that contains
        Parquet.dll or Parquet.Net.dll and its dependencies.

    .PARAMETER Path
        Specifies the directory where Parquet.NET assemblies will be installed.
        If not specified, defaults to the Path.DbatoolsParquet configuration value.

    .PARAMETER Version
        Specifies the Parquet.Net NuGet package version to install. Defaults to 5.4.0, the version used by Import-DbaParquet.
        Parquet.Net 5.5.0 and later ship a netstandard2.0 build whose read path throws NotImplementedException
        (StreamExtensions.CopyToAsync), which breaks Windows PowerShell, so do not bump this default until upstream fixes it.

    .PARAMETER LocalFile
        Specifies a local nupkg, zip file, or directory containing Parquet.dll or Parquet.Net.dll and its dependency DLLs.
        Use this for offline or pre-approved package installs. Local nupkg files only contain Parquet.NET itself, so
        dependency DLLs must also be present if installing without internet access.

    .PARAMETER Force
        Forces re-download and reinstallation even if Parquet.NET already exists in the target location.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Import, Parquet, Install
        Author: dbatools team

        Website: https://dbatools.io
        Copyright: (c) 2026 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Install-DbaParquet

    .OUTPUTS
        PSCustomObject

        Returns installation details when Parquet.NET is installed or already present.

        Properties:
        - Name: The primary assembly name
        - Path: The full file path to the Parquet.NET assembly
        - Version: The installed Parquet.NET file version
        - Installed: Boolean value of $true indicating successful installation

    .EXAMPLE
        PS C:\> Install-DbaParquet

        Downloads Parquet.NET and dependencies from NuGet and installs them to the dbatools data directory.

    .EXAMPLE
        PS C:\> Install-DbaParquet -Path C:\dbatools\parquet

        Installs Parquet.NET and dependencies to C:\dbatools\parquet.

    .EXAMPLE
        PS C:\> Install-DbaParquet -LocalFile C:\temp\parquet-libs.zip

        Installs Parquet.NET from a local zip file containing Parquet.dll and its dependencies.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [string]$Path,
        # Pinned to 5.4.0: the netstandard2.0 builds of Parquet.Net 5.5.0 through at least 6.0.3 throw
        # NotImplementedException in StreamExtensions.CopyToAsync when reading data pages, which breaks
        # every import on Windows PowerShell (no net4x target exists, so Desktop always gets netstandard2.0).
        [ValidateNotNullOrEmpty()]
        [string]$Version = "5.4.0",
        [string]$LocalFile,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        function Resolve-NuGetDependencyVersion {
            param (
                [Parameter(Mandatory)]
                [string]$VersionRange
            )

            $range = $VersionRange.Trim()
            if ($range -match "^\[(?<exact>[^,\]]+)\]$") {
                return $Matches.exact.Trim()
            }
            if ($range -match "^[\[\(]?(?<minimum>[^,\]\)]+)") {
                return $Matches.minimum.Trim()
            }
            return $range
        }

        function Get-NuGetPackageDownloadUrl {
            param (
                [Parameter(Mandatory)]
                [string]$PackageId,
                [Parameter(Mandatory)]
                [string]$PackageVersion
            )

            $lowerPackageId = $PackageId.ToLowerInvariant()
            $lowerVersion = $PackageVersion.ToLowerInvariant()
            "https://api.nuget.org/v3-flatcontainer/$lowerPackageId/$lowerVersion/$lowerPackageId.$lowerVersion.nupkg"
        }

        function Save-NuGetPackage {
            param (
                [Parameter(Mandatory)]
                [string]$PackageId,
                [Parameter(Mandatory)]
                [string]$PackageVersion,
                [Parameter(Mandatory)]
                [string]$PackageCache
            )

            if (-not (Test-Path -Path $PackageCache)) {
                $null = New-Item -Path $PackageCache -ItemType Directory -Force
            }

            $packageFileName = "$($PackageId.ToLowerInvariant()).$($PackageVersion.ToLowerInvariant()).nupkg"
            $packageFile = Join-Path -Path $PackageCache -ChildPath $packageFileName
            if ((Test-Path -Path $packageFile) -and -not $Force) {
                Write-Message -Level Verbose -Message "Using cached NuGet package $packageFile"
                return $packageFile
            }

            $url = Get-NuGetPackageDownloadUrl -PackageId $PackageId -PackageVersion $PackageVersion
            Write-Message -Level Verbose -Message "Downloading $PackageId $PackageVersion from $url"
            Invoke-TlsWebRequest -Uri $url -OutFile $packageFile -UseBasicParsing -ErrorAction Stop
            return $packageFile
        }

        function Expand-NuGetPackage {
            param (
                [Parameter(Mandatory)]
                [string]$PackageFile,
                [Parameter(Mandatory)]
                [string]$DestinationPath
            )

            # Use System.IO.Compression rather than Expand-Archive because Expand-Archive is PowerShell v5+
            # and silently skips entries it cannot translate (some NuGet packages contain files Expand-Archive
            # quietly drops, leading to "lib not found" failures downstream). dbatools must support PowerShell v3.
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            if (Test-Path -Path $DestinationPath) {
                Remove-Item -LiteralPath $DestinationPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            [System.IO.Compression.ZipFile]::ExtractToDirectory($PackageFile, $DestinationPath)
        }

        function Get-NuGetLibPath {
            param (
                [Parameter(Mandatory)]
                [string]$ExtractPath
            )

            $libRoot = Join-Path -Path $ExtractPath -ChildPath "lib"
            if (-not (Test-Path -Path $libRoot)) {
                return $null
            }

            # Pick the closest TFM to the host runtime. On .NET Core / .NET 5+ the netstandard2.0 builds
            # of Parquet.NET hit Span<T>/System.Memory ambiguity and throw NotImplementedException at
            # runtime, so we walk net*.0 down from the running major version first. On Windows PowerShell
            # we stay on .NET Framework targets.
            $psEdition = $PSVersionTable.PSEdition
            if (-not $psEdition) { $psEdition = "Desktop" }

            if ($psEdition -eq "Core") {
                $preferredFrameworks = @()
                $netMajor = [System.Environment]::Version.Major
                if ($netMajor -lt 5) { $netMajor = 8 }
                for ($i = $netMajor; $i -ge 5; $i--) {
                    $preferredFrameworks += "net$i.0"
                }
                $preferredFrameworks += @("netstandard2.1", "netcoreapp3.1", "netcoreapp3.0", "netstandard2.0")
            } else {
                $preferredFrameworks = @(
                    "net48",
                    "net472",
                    "net471",
                    "netstandard2.0",
                    "net462",
                    "net461",
                    "net46"
                )
            }

            foreach ($framework in $preferredFrameworks) {
                $candidate = Join-Path -Path $libRoot -ChildPath $framework
                if (Test-Path -Path $candidate) {
                    return $candidate
                }
            }

            $fallback = Get-ChildItem -Path $libRoot -Directory | Sort-Object Name | Select-Object -First 1
            if ($fallback) {
                return $fallback.FullName
            }
            return $null
        }

        function Get-NuGetDependencies {
            param (
                [Parameter(Mandatory)]
                [string]$ExtractPath
            )

            $nuspecFile = Get-ChildItem -Path $ExtractPath -Filter "*.nuspec" | Select-Object -First 1
            if (-not $nuspecFile) {
                return @()
            }

            [xml]$nuspec = Get-Content -Path $nuspecFile.FullName -Raw
            $dependencyGroups = @($nuspec.SelectNodes("//*[local-name()='dependencies']/*[local-name()='group']"))
            $dependencies = @()
            if ($dependencyGroups.Count -gt 0) {
                $selectedGroup = $dependencyGroups | Where-Object { $_.targetFramework -in ".NETStandard2.0", "netstandard2.0", "NETStandard2.0" } | Select-Object -First 1
                if (-not $selectedGroup) {
                    $selectedGroup = $dependencyGroups | Where-Object { -not $_.targetFramework } | Select-Object -First 1
                }
                if (-not $selectedGroup) {
                    $selectedGroup = $dependencyGroups | Where-Object { $_.targetFramework -match "netstandard" } | Sort-Object targetFramework | Select-Object -First 1
                }
                if ($selectedGroup) {
                    $dependencies = @($selectedGroup.SelectNodes("*[local-name()='dependency']"))
                }
            } else {
                $dependencies = @($nuspec.SelectNodes("//*[local-name()='dependencies']/*[local-name()='dependency']"))
            }

            foreach ($dependency in $dependencies) {
                if ($dependency.id -and $dependency.version) {
                    [PSCustomObject]@{
                        Id      = [string]$dependency.id
                        Version = Resolve-NuGetDependencyVersion -VersionRange ([string]$dependency.version)
                    }
                }
            }
        }

        function Compare-NuGetVersion {
            param (
                [Parameter(Mandatory)]
                [string]$Left,
                [Parameter(Mandatory)]
                [string]$Right
            )

            $leftClean = ($Left -split "-", 2)[0].Trim()
            $rightClean = ($Right -split "-", 2)[0].Trim()

            try {
                $leftVer = [System.Version]$leftClean
                $rightVer = [System.Version]$rightClean
                return $leftVer.CompareTo($rightVer)
            } catch {
                return [string]::Compare($leftClean, $rightClean, [System.StringComparison]::OrdinalIgnoreCase)
            }
        }

        function Resolve-NuGetPackageGraph {
            param (
                [Parameter(Mandatory)]
                [string]$PackageId,
                [Parameter(Mandatory)]
                [string]$PackageVersion,
                [Parameter(Mandatory)]
                [string]$PackageCache,
                [Parameter(Mandatory)]
                [string]$ExtractRoot,
                [Parameter(Mandatory)]
                [hashtable]$ResolvedPackages
            )

            # NuGet "highest minimum" resolution: when multiple deps require the same package id,
            # keep the highest minimum version instead of letting DFS order decide.
            $lowerId = $PackageId.ToLowerInvariant()
            if ($ResolvedPackages.ContainsKey($lowerId)) {
                $comparison = Compare-NuGetVersion -Left $PackageVersion -Right $ResolvedPackages[$lowerId].Version
                if ($comparison -le 0) {
                    return
                }
            }

            $packageFile = Save-NuGetPackage -PackageId $PackageId -PackageVersion $PackageVersion -PackageCache $PackageCache
            $extractPath = Join-Path -Path $ExtractRoot -ChildPath "$lowerId.$($PackageVersion.ToLowerInvariant())"
            Expand-NuGetPackage -PackageFile $packageFile -DestinationPath $extractPath

            $ResolvedPackages[$lowerId] = [PSCustomObject]@{
                Id          = $PackageId
                Version     = $PackageVersion
                ExtractPath = $extractPath
            }

            foreach ($dependency in Get-NuGetDependencies -ExtractPath $extractPath) {
                Resolve-NuGetPackageGraph -PackageId $dependency.Id -PackageVersion $dependency.Version -PackageCache $PackageCache -ExtractRoot $ExtractRoot -ResolvedPackages $ResolvedPackages
            }
        }

        function Copy-ResolvedAssemblies {
            param (
                [Parameter(Mandatory)]
                [hashtable]$ResolvedPackages,
                [Parameter(Mandatory)]
                [string]$DestinationPath
            )

            # Collect every candidate DLL from the resolved package set, keyed by filename.
            # When the same DLL ships in multiple packages, keep the highest file version so
            # transitive dependencies cannot regress newer assemblies pulled in by leaf packages.
            $dllsByName = @{ }
            foreach ($package in $ResolvedPackages.Values) {
                $libPath = Get-NuGetLibPath -ExtractPath $package.ExtractPath
                if (-not $libPath) {
                    Write-Message -Level Verbose -Message "No lib assets found for $($package.Id) $($package.Version)"
                    continue
                }

                Get-ChildItem -Path $libPath -Filter "*.dll" | ForEach-Object {
                    $key = $PSItem.Name.ToLowerInvariant()
                    if (-not $dllsByName.ContainsKey($key)) {
                        $dllsByName[$key] = $PSItem
                        return
                    }

                    $existingVersion = [System.Version]"0.0.0.0"
                    $candidateVersion = [System.Version]"0.0.0.0"
                    try { $existingVersion = [System.Version]$dllsByName[$key].VersionInfo.FileVersion } catch { }
                    try { $candidateVersion = [System.Version]$PSItem.VersionInfo.FileVersion } catch { }
                    if ($candidateVersion -gt $existingVersion) {
                        $dllsByName[$key] = $PSItem
                    }
                }
            }

            foreach ($file in $dllsByName.Values) {
                Copy-Item -Path $file.FullName -Destination $DestinationPath -Force
                Write-Message -Level Verbose -Message "Installed $($file.Name) ($($file.VersionInfo.FileVersion))"
            }
        }

        function Install-LocalParquetAssemblies {
            param (
                [Parameter(Mandatory)]
                [string]$SourcePath,
                [Parameter(Mandatory)]
                [string]$DestinationPath,
                [Parameter(Mandatory)]
                [string]$ExtractRoot
            )

            if (Test-Path -Path $SourcePath -PathType Container) {
                $sourceRoot = $SourcePath
            } else {
                $sourceRoot = Join-Path -Path $ExtractRoot -ChildPath "local"
                Expand-NuGetPackage -PackageFile $SourcePath -DestinationPath $sourceRoot
            }

            $libPath = Get-NuGetLibPath -ExtractPath $sourceRoot
            if ($libPath) {
                Get-ChildItem -Path $libPath -Filter "*.dll" | Copy-Item -Destination $DestinationPath -Force
            } else {
                Get-ChildItem -Path $sourceRoot -Filter "*.dll" -Recurse | Copy-Item -Destination $DestinationPath -Force
            }
        }

        function Remove-DbaParquetTempDirectory {
            param (
                [string]$TempPath
            )

            if (-not $TempPath) {
                return
            }

            try {
                $resolvedTempPath = [System.IO.Path]::GetFullPath($TempPath)
                $systemTempPath = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
                if ($resolvedTempPath.StartsWith($systemTempPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Remove-Item -LiteralPath $resolvedTempPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            } catch {
            }
        }
    }

    process {
        if ($Force) { $ConfirmPreference = "none" }

        if ($LocalFile -and $LocalFile.StartsWith("http")) {
            Stop-Function -Message "LocalFile cannot be a URL. It must be a local file path."
            return
        }

        if ($LocalFile -and -not (Test-Path -Path $LocalFile)) {
            Stop-Function -Message "LocalFile $LocalFile does not exist."
            return
        }

        Write-Progress -Activity "Installing Parquet.NET" -Status "Checking for existing installation..." -PercentComplete 0

        $installedPath = Get-DbaParquetPath -Silent
        if ($installedPath -and -not $Force) {
            Write-Progress -Activity "Installing Parquet.NET" -Completed
            $notes = "Parquet.NET already exists at $installedPath. Skipped installation. Use -Force to overwrite."
            Write-Message -Level Verbose -Message $notes
            [PSCustomObject]@{
                Name      = Split-Path -Path $installedPath -Leaf
                Path      = $installedPath
                Version   = (Get-Item -Path $installedPath).VersionInfo.FileVersion
                Installed = $true
                Notes     = $notes
            }
            return
        }

        if (-not $Path) {
            $Path = Get-DbatoolsConfigValue -FullName "Path.DbatoolsParquet"
            if (-not $Path) {
                $dbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"
                $dbatoolsData = $dbatoolsData.TrimEnd("/", "\")
                $Path = Join-Path -Path $dbatoolsData -ChildPath "parquet"
            }
        } else {
            Set-DbatoolsConfig -FullName "Path.DbatoolsParquet" -Value $Path
        }

        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatools-parquet-$([System.Guid]::NewGuid().ToString())"
        try {
            if (-not $PSCmdlet.ShouldProcess($Path, "Install Parquet.NET assemblies")) {
                Write-Progress -Activity "Installing Parquet.NET" -Completed
                return
            }

            Write-Progress -Activity "Installing Parquet.NET" -Status "Preparing installation directory..." -PercentComplete 10
            if (-not (Test-Path -Path $Path)) {
                $null = New-Item -Path $Path -ItemType Directory -Force
            }

            if (-not (Test-Path -Path $tempRoot)) {
                $null = New-Item -Path $tempRoot -ItemType Directory -Force
            }

            if ($LocalFile) {
                Write-Progress -Activity "Installing Parquet.NET" -Status "Installing local assemblies..." -PercentComplete 40
                Install-LocalParquetAssemblies -SourcePath $LocalFile -DestinationPath $Path -ExtractRoot $tempRoot
            } else {
                Write-Progress -Activity "Installing Parquet.NET" -Status "Resolving NuGet dependencies..." -PercentComplete 35
                $packageCache = Join-Path -Path $Path -ChildPath "packages"
                $extractRoot = Join-Path -Path $tempRoot -ChildPath "packages"
                $resolvedPackages = @{ }
                Resolve-NuGetPackageGraph -PackageId "Parquet.Net" -PackageVersion $Version -PackageCache $packageCache -ExtractRoot $extractRoot -ResolvedPackages $resolvedPackages
                Write-Progress -Activity "Installing Parquet.NET" -Status "Installing assemblies..." -PercentComplete 70
                Copy-ResolvedAssemblies -ResolvedPackages $resolvedPackages -DestinationPath $Path
            }

            Write-Progress -Activity "Installing Parquet.NET" -Status "Verifying installation..." -PercentComplete 90
            $parquetDllPath = Join-Path -Path $Path -ChildPath "Parquet.dll"
            if (-not (Test-Path -Path $parquetDllPath)) {
                $parquetDllPath = Join-Path -Path $Path -ChildPath "Parquet.Net.dll"
            }
            if (Test-Path -Path $parquetDllPath) {
                Write-Progress -Activity "Installing Parquet.NET" -Completed
                [PSCustomObject]@{
                    Name      = Split-Path -Path $parquetDllPath -Leaf
                    Path      = $parquetDllPath
                    Version   = (Get-Item -Path $parquetDllPath).VersionInfo.FileVersion
                    Installed = $true
                }
            } else {
                Write-Progress -Activity "Installing Parquet.NET" -Completed
                Stop-Function -Message "Parquet.NET installation failed. Parquet.dll was not found in $Path."
            }
        } catch {
            Write-Progress -Activity "Installing Parquet.NET" -Completed
            Stop-Function -Message "Failed to install Parquet.NET. $_" -ErrorRecord $_
        } finally {
            Remove-DbaParquetTempDirectory -TempPath $tempRoot
        }
    }
}

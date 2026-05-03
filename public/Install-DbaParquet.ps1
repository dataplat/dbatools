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
        Specifies the Parquet.Net NuGet package version to install. Defaults to 5.5.0, the version used by Import-DbaParquet.

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
        [ValidateNotNullOrEmpty()]
        [string]$Version = "5.5.0",
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

            if (-not (Test-Path -Path $DestinationPath)) {
                $null = New-Item -Path $DestinationPath -ItemType Directory -Force
            }

            $archivePath = $PackageFile
            if (-not $PackageFile.EndsWith(".zip", [System.StringComparison]::OrdinalIgnoreCase)) {
                $archivePath = Join-Path -Path ([System.IO.Path]::GetDirectoryName($PackageFile)) -ChildPath "$([System.IO.Path]::GetFileName($PackageFile)).zip"
                Copy-Item -Path $PackageFile -Destination $archivePath -Force
            }

            Expand-Archive -LiteralPath $archivePath -DestinationPath $DestinationPath -Force
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

            $preferredFrameworks = @(
                "netstandard2.0",
                "netstandard2.1",
                "net8.0",
                "net7.0",
                "net6.0",
                "net461",
                "net462",
                "net472",
                "net48"
            )

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

        function Copy-NuGetLibAssemblies {
            param (
                [Parameter(Mandatory)]
                [string]$ExtractPath,
                [Parameter(Mandatory)]
                [string]$DestinationPath
            )

            $libPath = Get-NuGetLibPath -ExtractPath $ExtractPath
            if (-not $libPath) {
                Write-Message -Level Verbose -Message "No lib assets found in $ExtractPath"
                return
            }

            Get-ChildItem -Path $libPath -Filter "*.dll" | ForEach-Object {
                Copy-Item -Path $PSItem.FullName -Destination $DestinationPath -Force
                Write-Message -Level Verbose -Message "Installed $($PSItem.Name)"
            }
        }

        function Install-NuGetPackageWithDependencies {
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
                [string]$DestinationPath,
                [Parameter(Mandatory)]
                [hashtable]$VisitedPackages
            )

            $visitKey = "$($PackageId.ToLowerInvariant())|$($PackageVersion.ToLowerInvariant())"
            if ($VisitedPackages[$visitKey]) {
                return
            }
            $VisitedPackages[$visitKey] = $true

            $packageFile = Save-NuGetPackage -PackageId $PackageId -PackageVersion $PackageVersion -PackageCache $PackageCache
            $extractPath = Join-Path -Path $ExtractRoot -ChildPath $visitKey.Replace("|", ".")
            Expand-NuGetPackage -PackageFile $packageFile -DestinationPath $extractPath
            Copy-NuGetLibAssemblies -ExtractPath $extractPath -DestinationPath $DestinationPath

            foreach ($dependency in Get-NuGetDependencies -ExtractPath $extractPath) {
                Install-NuGetPackageWithDependencies -PackageId $dependency.Id -PackageVersion $dependency.Version -PackageCache $PackageCache -ExtractRoot $ExtractRoot -DestinationPath $DestinationPath -VisitedPackages $VisitedPackages
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
                Write-Progress -Activity "Installing Parquet.NET" -Status "Downloading NuGet packages..." -PercentComplete 35
                $packageCache = Join-Path -Path $Path -ChildPath "packages"
                $extractRoot = Join-Path -Path $tempRoot -ChildPath "packages"
                $visitedPackages = @{ }
                Install-NuGetPackageWithDependencies -PackageId "Parquet.Net" -PackageVersion $Version -PackageCache $packageCache -ExtractRoot $extractRoot -DestinationPath $Path -VisitedPackages $visitedPackages
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

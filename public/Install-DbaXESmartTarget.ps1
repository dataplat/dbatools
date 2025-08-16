function Install-DbaXESmartTarget {
    <#
    .SYNOPSIS
        Downloads and installs XESmartTarget on Windows and Linux

    .DESCRIPTION
        Downloads and installs XESmartTarget so that you can use it to process SQL Server Extended Events.

        XESmartTarget is a configurable target for SQL Server Extended Events that allows you to write to a table
        or perform custom actions with no effort. It connects to an Extended Events session running on a SQL Server
        instance and can perform actions in response to events captured by the session.

        Cross-platform support:
        - Windows: Supports both MSI (extracted) and standalone executable installation methods
        - Linux: Supports ZIP installation method only

        By default, XESmartTarget is installed as a portable application to the dbatools directory.

        Writes to $script:PSModuleRoot\bin\xesmarttarget by default.

    .PARAMETER Path
        Specifies the path where XESmartTarget will be extracted or installed.
        If not specified, XESmartTarget will be installed to the dbatools directory.

    .PARAMETER Type
        Specifies the installation type. Valid values are:
        - Msi: Downloads and extracts the MSI package (Windows only, default for Windows)
        - Exe: Downloads the standalone executable (Windows only)
        - Zip: Downloads and extracts the ZIP file (Linux only, default for Linux)

    .PARAMETER Version
        Specifies the version to download. If not specified, downloads the latest release.
        Use format like "2.0.4.0" for specific versions.

    .PARAMETER LocalFile
        Specifies the path to a local file to install XESmartTarget from. This file should be an msi, zip, or exe file.

    .PARAMETER Force
        If this switch is enabled, XESmartTarget will be downloaded from the internet even if previously cached.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvents, XESmartTarget, Install
        Author: Chrissy LeMaire and Claude

        Website: https://dbatools.io
        Copyright: (c) 2025 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        XESmartTarget Project: https://github.com/spaghettidba/XESmartTarget

    .LINK
        https://dbatools.io/Install-DbaXESmartTarget

    .EXAMPLE
        PS C:\> Install-DbaXESmartTarget

        Downloads XESmartTarget MSI and extracts it to the dbatools directory (Windows), or downloads ZIP (Linux)

    .EXAMPLE
        PS C:\> Install-DbaXESmartTarget -Type Exe

        Downloads the standalone XESmartTarget.exe file (Windows only)

    .EXAMPLE
        PS C:\> Install-DbaXESmartTarget -Path C:\XESmartTarget

        Downloads XESmartTarget to C:\XESmartTarget

    .EXAMPLE
        PS C:\> Install-DbaXESmartTarget -Version "2.0.4.0"

        Downloads and installs XESmartTarget version 2.0.4.0

    .EXAMPLE
        PS C:\> Install-DbaXESmartTarget -LocalFile C:\temp\XESmartTarget-2.0.4.0.msi

        Extracts XESmartTarget from the local MSI file.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [string]$Path,
        [ValidateSet("Msi", "Exe", "Zip")]
        [string]$Type,
        [string]$Version,
        [string]$LocalFile,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        Write-Progress -Activity "Installing XESmartTarget" -Status "Initializing..." -PercentComplete 0

        if ($Force) { $ConfirmPreference = 'none' }

        # Set default type based on platform if not specified
        if (-not $Type) {
            if ($PSVersionTable.Platform -eq "Unix") {
                $Type = "Zip"
            } else {
                $Type = "Msi"
            }
        }

        # Platform-specific validations
        if ($PSVersionTable.Platform -eq "Unix") {
            # Unix platforms only support Zip type
            if ($Type -in @("Msi", "Exe")) {
                Write-Progress -Activity "Installing XESmartTarget" -Completed
                Stop-Function -Message "MSI and EXE installation types are only supported on Windows. Use Zip type on Unix platforms."
                return
            }
        } else {
            # Windows-specific validation for Zip type
            if ($Type -eq "Zip") {
                Write-Progress -Activity "Installing XESmartTarget" -Completed
                Stop-Function -Message "ZIP installation type is for Linux. Use Msi or Exe types on Windows."
                return
            }
        }

        # Set default path if not specified
        if (-not $Path) {
            # Install to dbatools data directory like SqlPackage
            $dbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"
            # Normalize path to remove any trailing slashes before joining
            $dbatoolsData = $dbatoolsData.TrimEnd('/', '\')
            $Path = Join-Path -Path $dbatoolsData -ChildPath "xesmarttarget"
        }

        Write-Progress -Activity "Installing XESmartTarget" -Status "Determining download URLs..." -PercentComplete 5

        # Determine URLs and file names based on type and platform
        if ($Type -eq "Zip") {
            # Linux ZIP
            $fileName = "XESmartTarget-linux.zip"
            $assetPattern = "XESmartTarget-linux-*.zip"
        } elseif ($Type -eq "Exe") {
            # Windows standalone executable
            $fileName = "XESmartTarget.exe"
            $assetPattern = "XESmartTarget.exe"
        } else {
            # Windows MSI
            $fileName = "XESmartTarget.msi"
            $assetPattern = "XESmartTarget-*.msi"
        }

        # Build GitHub API URL for releases
        $apiUrl = "https://api.github.com/repos/spaghettidba/XESmartTarget/releases"
        if ($Version) {
            $apiUrl += "/tags/$Version"
        } else {
            $apiUrl += "/latest"
        }

        $temp = ([System.IO.Path]::GetTempPath())
        $localCachedCopy = Join-Path -Path $temp -ChildPath $fileName

        if (-not $LocalFile) {
            $LocalFile = $localCachedCopy
        }

        Write-Progress -Activity "Installing XESmartTarget" -Status "Validating installation..." -PercentComplete 10
    }

    process {
        if (Test-FunctionInterrupt) { return }

        Write-Progress -Activity "Installing XESmartTarget" -Status "Checking for existing installation..." -PercentComplete 15

        # Check if XESmartTarget already exists
        if (-not $LocalFile.StartsWith("http") -and -not (Test-Path -Path $LocalFile) -and -not $Force) {
            if (-not (Test-Path -Path $localCachedCopy)) {
                Write-Message -Level Verbose -Message "No local file exists. Downloading now."
                if ((Test-Path -Path $localCachedCopy) -and (Test-Path -Path $Path) -and -not $Force) {
                    Write-Message -Level Warning -Message "XESmartTarget already exists at $Path. Skipping download. Use -Force to overwrite."
                    Write-Progress -Activity "Installing XESmartTarget" -Completed
                    return
                }
            }
        }

        if (-not $LocalFile.StartsWith("http") -and (Test-Path -Path $localCachedCopy) -and (Test-Path -Path $Path) -and -not $Force) {
            Write-Message -Level Verbose -Message "XESmartTarget already exists at $Path. Skipping download."
            Write-Message -Level Verbose -Message "Use -Force to overwrite."
            Write-Progress -Activity "Installing XESmartTarget" -Completed
            return
        }

        # Download if needed
        if ($LocalFile.StartsWith("http") -or -not (Test-Path -Path $LocalFile) -or $Force) {
            Write-Progress -Activity "Installing XESmartTarget" -Status "Getting release information from GitHub..." -PercentComplete 20
            Write-Message -Level Verbose -Message "Fetching release information from $apiUrl"

            try {
                $releaseInfo = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing

                # Find the correct asset based on type
                $asset = $releaseInfo.assets | Where-Object { $_.name -like $assetPattern } | Select-Object -First 1

                if (-not $asset) {
                    Write-Progress -Activity "Installing XESmartTarget" -Completed
                    Stop-Function -Message "Could not find $Type package in the release assets."
                    return
                }

                $downloadUrl = $asset.browser_download_url
                Write-Message -Level Verbose -Message "Found download URL: $downloadUrl"

            } catch {
                Write-Progress -Activity "Installing XESmartTarget" -Completed
                Stop-Function -Message "Failed to get release information from GitHub: $_" -ErrorRecord $_
                return
            }

            Write-Progress -Activity "Installing XESmartTarget" -Status "Starting download from GitHub..." -PercentComplete 25
            Write-Message -Level Verbose -Message "Downloading XESmartTarget from $downloadUrl"

            try {
                Write-Progress -Activity "Installing XESmartTarget" -Status "Downloading XESmartTarget package..." -PercentComplete 30
                try {
                    Invoke-TlsWebRequest -Uri $downloadUrl -OutFile $LocalFile -UseBasicParsing
                } catch {
                    Write-Progress -Activity "Installing XESmartTarget" -Status "Retrying download with proxy settings..." -PercentComplete 33
                    # Try with default proxy and user settings
                    (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                    Invoke-TlsWebRequest -Uri $downloadUrl -OutFile $LocalFile -UseBasicParsing
                }
                Write-Progress -Activity "Installing XESmartTarget" -Status "Download completed successfully" -PercentComplete 50
            } catch {
                Write-Progress -Activity "Installing XESmartTarget" -Completed
                Stop-Function -Message "Couldn't download XESmartTarget. Download failed: $_" -ErrorRecord $_
                return
            }
        }

        Write-Progress -Activity "Installing XESmartTarget" -Status "Preparing installation..." -PercentComplete 55

        # Install XESmartTarget
        if ($Pscmdlet.ShouldProcess("$LocalFile", "Install XESmartTarget")) {
            if ($LocalFile.StartsWith("http")) {
                Write-Progress -Activity "Installing XESmartTarget" -Completed
                Stop-Function -Message "LocalFile cannot be a URL. It must be a local file path."
                return
            }

            if (-not (Test-Path -Path $LocalFile)) {
                Write-Progress -Activity "Installing XESmartTarget" -Completed
                Stop-Function -Message "LocalFile $LocalFile does not exist."
                return
            }

            if (-not (Test-Path -Path $Path)) {
                $null = New-Item -ItemType Directory -Path $Path -Force
            }

            # Remove existing files if Force is specified
            if ($Force -and (Test-Path -Path $Path)) {
                Remove-Item -Path "$Path\*" -Recurse -Force -ErrorAction SilentlyContinue
            }

            if ($LocalFile.EndsWith(".msi") -or $Type -eq "Msi") {
                Write-Progress -Activity "Installing XESmartTarget" -Status "Extracting MSI package..." -PercentComplete 70
                Write-Message -Level Verbose -Message "Extracting XESmartTarget MSI to $Path"

                # Extract MSI using msiexec
                try {
                    $msiArgs = @(
                        "/a"
                        "`"$LocalFile`""
                        "/qn"
                        "TARGETDIR=`"$Path`""
                    )
                    $msiArguments = $msiArgs -join " "
                    Write-Message -Level Verbose -Message "Extracting with: msiexec $msiArguments"
                    $process = Start-Process -FilePath msiexec -ArgumentList $msiArguments -Wait -PassThru -NoNewWindow
                    if ($process.ExitCode -ne 0) {
                        Write-Progress -Activity "Installing XESmartTarget" -Completed
                        Stop-Function -Message "Failed to extract XESmartTarget from $LocalFile. Exit code: $($process.ExitCode)"
                        return
                    }
                } catch {
                    Write-Progress -Activity "Installing XESmartTarget" -Completed
                    Stop-Function -Message "Unable to extract XESmartTarget from MSI: $_" -ErrorRecord $_
                    return
                }
            } elseif ($LocalFile.EndsWith(".exe") -or $Type -eq "Exe") {
                Write-Progress -Activity "Installing XESmartTarget" -Status "Copying executable..." -PercentComplete 70
                Write-Message -Level Verbose -Message "Copying XESmartTarget.exe to $Path"

                try {
                    $destinationPath = Join-Path -Path $Path -ChildPath "XESmartTarget.exe"
                    Copy-Item -Path $LocalFile -Destination $destinationPath -Force:$Force
                } catch {
                    Write-Progress -Activity "Installing XESmartTarget" -Completed
                    Stop-Function -Message "Unable to copy XESmartTarget.exe to $Path. $_" -ErrorRecord $_
                    return
                }
            } else {
                Write-Progress -Activity "Installing XESmartTarget" -Status "Extracting ZIP archive..." -PercentComplete 70
                Write-Message -Level Verbose -Message "Extracting XESmartTarget zip to $Path"

                # Unpack archive
                try {
                    Expand-Archive -Path $LocalFile -DestinationPath $Path -Force:$Force

                    # Make executable on Unix platforms
                    if ($PSVersionTable.Platform -eq "Unix") {
                        $executablePath = Join-Path $Path "XESmartTarget"
                        if (Test-Path $executablePath) {
                            try {
                                & chmod "+x" $executablePath 2>$null
                            } catch {
                                Write-Message -Level Warning -Message "Could not make XESmartTarget executable. You may need to run 'chmod +x $executablePath' manually."
                            }
                        }
                        # Also check subfolders
                        $subfolderExecutables = Get-ChildItem -Path "$Path/*/XESmartTarget" -ErrorAction SilentlyContinue
                        foreach ($exe in $subfolderExecutables) {
                            try {
                                & chmod "+x" $exe.FullName 2>$null
                            } catch {
                                Write-Message -Level Warning -Message "Could not make $($exe.FullName) executable."
                            }
                        }
                    }
                } catch {
                    Write-Progress -Activity "Installing XESmartTarget" -Completed
                    Stop-Function -Message "Unable to extract XESmartTarget to $Path. $_" -ErrorRecord $_
                    return
                }
            }
        }

        Write-Progress -Activity "Installing XESmartTarget" -Status "Verifying installation..." -PercentComplete 90

        # Verify installation
        if ($PSVersionTable.Platform -eq "Unix") {
            $xeSmartTargetPaths = @(
                "$Path/XESmartTarget"
                "$Path/*/XESmartTarget"  # In case it extracts to a subfolder
            )
        } else {
            $xeSmartTargetPaths = @(
                "$Path\XESmartTarget.exe"
                "$Path\*\XESmartTarget.exe"  # In case it extracts to a subfolder
                "$Path\PFiles\XESmartTarget\XESmartTarget.exe"  # MSI might create PFiles structure
            )
        }

        $xeSmartTargetFound = $false
        $installedPath = $null
        foreach ($xePath in $xeSmartTargetPaths) {
            $foundPaths = Get-ChildItem -Path $xePath -ErrorAction SilentlyContinue
            if ($foundPaths) {
                $xeSmartTargetFound = $true
                $installedPath = $foundPaths[0].FullName
                Write-Message -Level Verbose -Message "XESmartTarget found at: $installedPath"
                break
            }
        }

        Write-Progress -Activity "Installing XESmartTarget" -Status "Installation completed!" -PercentComplete 100
        Start-Sleep -Milliseconds 500
        Write-Progress -Activity "Installing XESmartTarget" -Completed

        if ($xeSmartTargetFound) {
            Write-Message -Level Verbose -Message "XESmartTarget installed successfully"
            # Return the installation information
            [PSCustomObject]@{
                Name      = if ($PSVersionTable.Platform -eq "Unix") { "XESmartTarget" } else { "XESmartTarget.exe" }
                Path      = $installedPath
                Installed = $true
                Type      = $Type
            }
        } else {
            Stop-Function -Message "XESmartTarget installation failed - XESmartTarget executable not found in expected locations"
        }
    }
}
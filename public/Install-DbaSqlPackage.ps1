function Install-DbaSqlPackage {
    <#
    .SYNOPSIS
        Installs SqlPackage on Windows, Linux, or macOS using the appropriate method for each platform.

    .DESCRIPTION
        This function detects the operating system and installs SqlPackage using the most appropriate method:
        - Windows: Prefers dotnet tool install, falls back to MSI installer
        - Linux: Uses dotnet tool install with automatic .NET SDK installation if needed
        - macOS: Uses dotnet tool install with Homebrew .NET SDK installation if needed

        SqlPackage is required for DACPAC/BACPAC operations and is used by Export-DbaDacPackage and other dbatools functions.

    .PARAMETER Method
        Specifies the installation method to use. Valid options:
        - DotnetTool: Install as a global .NET tool (requires existing .NET SDK)
        - MSI: Windows only - Install using the DacFx MSI installer
        - Zip: Download and extract the standalone zip package (Default)

    .PARAMETER Force
        Forces installation even if SqlPackage is already detected on the system.

    .PARAMETER Version
        Specifies a specific version of SqlPackage to install. If not specified, installs the latest version.
        Example: "170.1.61"

    .PARAMETER Scope
        When using DotnetTool method, specifies the installation scope:
        - Global (default): Install as a global tool available system-wide
        - CurrentUser: Install as a local tool in the current directory

    .PARAMETER InstallPath
        When using Zip method, specifies the installation directory.
        Defaults to:
        - Windows: "$env:ProgramFiles\SqlPackage"
        - Linux/macOS: "/usr/local/sqlpackage"

    .PARAMETER AddToPath
        When using Zip method, adds the installation directory to the system PATH.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SqlPackage, Installation, DACPAC, BACPAC
        Author: Chrissy LeMaire (@funbucket), dbatools.io

        Website: https://dbatools.io
        Copyright: (c) 2025 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Install-DbaSqlPackage

    .EXAMPLE
        PS C:\> Install-DbaSqlPackage

        Uses the standalone Zip method to install SqlPackage without requiring .NET SDK.
        This is the default method that works on all platforms.

    .EXAMPLE
        PS C:\> Install-DbaSqlPackage -Method DotnetTool -Version "170.1.61"

        Installs SqlPackage version 170.1.61 as a global .NET tool (requires existing .NET SDK).

    .EXAMPLE
        PS C:\> Install-DbaSqlPackage -Method MSI -Force

        Forces installation of SqlPackage using the MSI installer on Windows, even if already installed.

    .EXAMPLE
        PS C:\> Install-DbaSqlPackage -Method Zip -InstallPath "C:\Tools\SqlPackage" -AddToPath

        Downloads the standalone SqlPackage zip, extracts to C:\Tools\SqlPackage, and adds it to PATH.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [ValidateSet('DotnetTool', 'MSI', 'Zip')]
        [string]$Method = 'Zip',
        [switch]$Force,
        [string]$Version,
        [ValidateSet('Global', 'CurrentUser')]
        [string]$Scope = 'CurrentUser',
        [string]$InstallPath,
        [switch]$AddToPath,
        [switch]$EnableException
    )

    begin {
        # Check if SqlPackage is already available
        $existingSqlPackage = Get-Command sqlpackage -ErrorAction SilentlyContinue
        if ($existingSqlPackage -and -not $Force) {
            Write-Message -Level Output -Message "SqlPackage is already available at: $($existingSqlPackage.Source)"
            Write-Message -Level Output -Message "Use -Force to reinstall or upgrade."
            return [PSCustomObject]@{
                Status  = "Already Installed"
                Path    = $existingSqlPackage.Source
                Version = $null
                Method  = "Existing"
            }
        }

        # Validate method compatibility with OS
        if ($Method -eq 'MSI' -and -not $isWindows) {
            Stop-Function -Message "MSI installation method is only supported on Windows" -EnableException:$EnableException
            return
        }

        # Set default install path for Zip method
        if ($Method -eq 'Zip' -and -not $InstallPath) {
            if ($isWindows) {
                $InstallPath = "$env:ProgramFiles\SqlPackage"
            } else {
                $InstallPath = "/usr/local/sqlpackage"
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        try {
            switch ($Method) {
                'DotnetTool' {
                    Write-Message -Level Output -Message "Installing SqlPackage as .NET global tool..."

                    # Check if .NET SDK is available
                    $dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
                    if (-not $dotnetCmd) {
                        Stop-Function -Message ".NET SDK is required for DotnetTool method but was not found. Use -Method Zip for standalone installation without .NET SDK dependency." -EnableException:$EnableException
                        return
                    }

                    # Install SqlPackage as dotnet tool
                    $installArgs = @('tool', 'install', '--global', 'Microsoft.SqlPackage')
                    if ($Scope -eq 'CurrentUser') {
                        $installArgs = @('tool', 'install', '--local', 'Microsoft.SqlPackage')
                    }
                    if ($Version) {
                        $installArgs += @('--version', $Version)
                    }
                    if ($Force) {
                        # Remove existing installation first
                        try {
                            & dotnet tool uninstall --global Microsoft.SqlPackage 2>$null
                        } catch {
                            # Ignore errors if not installed
                        }
                    }

                    Write-Message -Level Verbose -Message "Running: dotnet $($installArgs -join ' ')"
                    $result = & dotnet @installArgs 2>&1

                    if ($LASTEXITCODE -ne 0) {
                        Stop-Function -Message "Failed to install SqlPackage via dotnet tool: $result" -EnableException:$EnableException
                        return
                    }

                    Write-Message -Level Output -Message "SqlPackage installed successfully as .NET global tool"
                    $installMethod = "DotnetTool"
                    $installPath = if ($Scope -eq 'Global') {
                        if ($isWindows) { "$env:USERPROFILE\.dotnet\tools" } else { "$HOME/.dotnet/tools" }
                    } else {
                        (Get-Location).Path
                    }
                }
                'MSI' {
                    Write-Message -Level Output -Message "Installing SqlPackage using MSI installer..."

                    $tempPath = [System.IO.Path]::GetTempPath()
                    $msiPath = Join-Path $tempPath "DacFramework.msi"

                    try {
                        Write-Message -Level Output -Message "Downloading DacFramework MSI..."
                        Invoke-WebRequest -Uri "https://aka.ms/dacfx-msi" -OutFile $msiPath

                        Write-Message -Level Output -Message "Installing MSI package..."
                        $installArgs = @("/i", "`"$msiPath`"", "/quiet", "/norestart")
                        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru

                        if ($process.ExitCode -ne 0) {
                            Stop-Function -Message "MSI installation failed with exit code: $($process.ExitCode)" -EnableException:$EnableException
                            return
                        }

                        Write-Message -Level Output -Message "SqlPackage installed successfully via MSI"
                        $installMethod = "MSI"
                        $installPath = "${env:ProgramFiles(x86)}\Microsoft SQL Server\170\DAC\bin"

                    } finally {
                        if (Test-Path $msiPath) {
                            Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                'Zip' {
                    Write-Message -Level Output -Message "Installing SqlPackage from zip download..."

                    # Determine download URL based on OS
                    if ($isWindows) {
                        $downloadUrl = "https://aka.ms/sqlpackage-windows"
                        $executableName = "SqlPackage.exe"
                    } elseif ($isLinux) {
                        $downloadUrl = "https://aka.ms/sqlpackage-linux"
                        $executableName = "sqlpackage"
                    } elseif ($isMacOS) {
                        $downloadUrl = "https://aka.ms/sqlpackage-macos"
                        $executableName = "sqlpackage"
                    }

                    $tempPath = [System.IO.Path]::GetTempPath()
                    $zipPath = Join-Path $tempPath "sqlpackage.zip"

                    try {
                        Write-Message -Level Output -Message "Downloading SqlPackage from $downloadUrl..."
                        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath

                        Write-Message -Level Output -Message "Creating installation directory: $InstallPath"

                        if (-not (Test-Path $InstallPath)) {
                            $null = New-Item -ItemType Directory -Path $InstallPath -Force
                        }

                        Write-Message -Level Output -Message "Extracting SqlPackage to $InstallPath..."
                        if ($isWindows) {
                            Add-Type -AssemblyName System.IO.Compression.FileSystem
                            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $InstallPath)
                        } else {
                            Invoke-Expression "unzip -q '$zipPath' -d '$InstallPath'"
                        }

                        # Make executable on Linux/macOS
                        if (-not $isWindows) {
                            $executablePath = Join-Path $InstallPath $executableName
                            if (Test-Path $executablePath) {
                                Invoke-Expression "chmod +x '$executablePath'"
                            }
                        }

                        # Add to PATH if requested
                        if ($AddToPath) {
                            Write-Message -Level Output -Message "Adding $InstallPath to PATH..."

                            if ($isWindows) {
                                $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
                                if ($currentPath -notlike "*$InstallPath*") {
                                    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$InstallPath", "Machine")
                                    $env:PATH = "$env:PATH;$InstallPath"
                                }
                            } else {
                                # Add to shell profile
                                $profileFiles = @("~/.bashrc", "~/.bash_profile", "~/.zshrc", "~/.zprofile")
                                $pathExport = "export PATH=`"`$PATH:$InstallPath`""

                                foreach ($profileFile in $profileFiles) {
                                    if (Test-Path $profileFile) {
                                        $content = Get-Content $profileFile -Raw -ErrorAction SilentlyContinue
                                        if ($content -notlike "*$InstallPath*") {
                                            Add-Content -Path $profileFile -Value $pathExport
                                        }
                                    }
                                }

                                # Update current session PATH
                                $env:PATH = "$env:PATH:$InstallPath"
                            }
                        }

                        Write-Message -Level Output -Message "SqlPackage installed successfully from zip"
                        $installMethod = "Zip"

                    } finally {
                        if (Test-Path $zipPath) {
                            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }

            # Verify installation
            Write-Message -Level Output -Message "Verifying SqlPackage installation..."
            Start-Sleep -Seconds 2  # Allow time for PATH updates

            $sqlPackageCmd = Get-Command sqlpackage -ErrorAction SilentlyContinue
            if ($sqlPackageCmd) {
                try {
                    $versionOutput = & sqlpackage /version 2>&1
                    $installedVersion = if ($versionOutput -match "(\d+\.\d+\.\d+)") { $matches[1] } else { "Unknown" }
                } catch {
                    $installedVersion = "Unknown"
                }

                Write-Message -Level Output -Message "SqlPackage installation verified successfully!"
                Write-Message -Level Output -Message "Location: $($sqlPackageCmd.Source)"
                Write-Message -Level Output -Message "Version: $installedVersion"

                [PSCustomObject]@{
                    Status      = "Successfully Installed"
                    Path        = $sqlPackageCmd.Source
                    Version     = $installedVersion
                    Method      = $installMethod
                    InstallPath = $installPath
                }

            } else {
                Stop-Function -Message "SqlPackage installation completed but sqlpackage command not found in PATH. You may need to restart your shell or manually add the installation directory to your PATH." -EnableException:$EnableException
                return
            }

        } catch {
            Stop-Function -Message "Installation failed: $($_.Exception.Message)" -ErrorRecord $_ -EnableException:$EnableException
            return
        }
    }
}
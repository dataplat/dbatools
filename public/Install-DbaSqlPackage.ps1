function Install-DbaSqlPackage {
    <#
    .SYNOPSIS
        Downloads and installs SqlPackage on Windows, Linux, or macOS

    .DESCRIPTION
        Downloads and installs SqlPackage so that you can use Import-DbaDacpac, Export-DbaDacpac, Publish-DbaDacpac and Get-DbaDacpac.

        Cross-platform support:
        - Windows: Supports both ZIP (portable) and MSI installation methods
        - Linux/macOS: Supports ZIP installation method only

        By default, SqlPackage is installed as a portable ZIP file to the dbatools directory for CurrentUser scope.
        For AllUsers (LocalMachine) scope on Windows, you can use the MSI installer which requires administrative privileges.

        Writes to $script:PSModuleRoot\bin\sqlpackage by default for CurrentUser scope.

    .PARAMETER Path
        Specifies the path where SqlPackage will be extracted or installed.
        If not specified, SqlPackage will be installed to the dbatools directory for CurrentUser scope.

    .PARAMETER Scope
        Specifies the installation scope. Valid values are:
        - CurrentUser: Installs to the dbatools directory (default, uses ZIP)
        - AllUsers: Installs to system location (Windows: Program Files with MSI/admin privileges; Unix: /usr/local/sqlpackage)

    .PARAMETER Type
        Specifies the installation type. Valid values are:
        - Zip: Downloads and extracts the portable ZIP file (default, works on all platforms)
        - Msi: Downloads and installs the MSI package (Windows only, AllUsers scope only, requires admin privileges)

    .PARAMETER LocalFile
        Specifies the path to a local file to install SqlPackage from. This file should be an msi or zip file.

    .PARAMETER Force
        If this switch is enabled, the Sqlpackage will be downloaded from the internet even if previously cached.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Deployment, Install
        Author: Chrissy LeMaire and Claude

        Website: https://dbatools.io
        Copyright: (c) 2025 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Install-DbaSqlPackage

    .EXAMPLE
        PS C:\> Install-DbaSqlPackage

        Downloads SqlPackage ZIP to the dbatools directory for the current user

    .EXAMPLE
        PS C:\> Install-DbaSqlPackage -Scope AllUsers -Type Msi

        Downloads and installs SqlPackage MSI for all users (requires administrative privileges)

    .EXAMPLE
        PS C:\> Install-DbaSqlPackage -Path C:\SqlPackage

        Downloads SqlPackage ZIP to C:\SqlPackage

    .EXAMPLE
        PS C:\> Install-DbaSqlPackage -LocalFile C:\temp\sqlpackage.zip

        Installs SqlPackage from the local ZIP file.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [string]$Path,
        [ValidateSet("CurrentUser", "AllUsers")]
        [string]$Scope = "CurrentUser",
        [ValidateSet("Zip", "Msi")]
        [string]$Type = "Zip",
        [string]$LocalFile,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        Write-Progress -Activity "Installing SqlPackage" -Status "Initializing..." -PercentComplete 0

        if ($Force) { $ConfirmPreference = 'none' }

        # Set default path based on scope and platform if not specified
        if (-not $Path) {
            if ($Scope -eq "CurrentUser") {
                # Install to dbatools data directory
                $dbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"
                # Normalize path to remove any trailing slashes before joining
                $dbatoolsData = $dbatoolsData.TrimEnd('/', '\')
                $Path = Join-Path -Path $dbatoolsData -ChildPath "sqlpackage"
            } else {
                # AllUsers scope uses platform-specific default location
                if ($PSVersionTable.Platform -eq "Unix") {
                    $Path = "/usr/local/sqlpackage"
                } else {
                    $Path = "${env:ProgramFiles}\Microsoft SQL Server\DAC\bin"
                }
            }
        }

        Write-Progress -Activity "Installing SqlPackage" -Status "Determining download URLs..." -PercentComplete 5

        # Determine URLs based on type and platform
        if ($Type -eq "Zip") {
            if ($PSVersionTable.Platform -eq "Unix") {
                if ($IsLinux) {
                    $url = "https://aka.ms/sqlpackage-linux"
                } elseif ($IsMacOS) {
                    $url = "https://aka.ms/sqlpackage-macos"
                } else {
                    $url = "https://aka.ms/sqlpackage-linux"  # Default to Linux for other Unix
                }
            } else {
                $url = "https://aka.ms/sqlpackage-windows"  # Windows .NET 8 ZIP (portable)
            }
            $fileName = "sqlpackage.zip"
        } else {
            $url = "https://aka.ms/dacfx-msi"  # Windows .NET Framework MSI
            $fileName = "dacfx.msi"
        }

        $temp = ([System.IO.Path]::GetTempPath())
        $localCachedCopy = Join-Path -Path $temp -ChildPath $fileName

        if (-not $LocalFile) {
            $LocalFile = $localCachedCopy
        }

        Write-Progress -Activity "Installing SqlPackage" -Status "Validating platform and permissions..." -PercentComplete 10

        # Platform-specific validations
        if ($PSVersionTable.Platform -eq "Unix") {
            # Unix platforms only support Zip type and CurrentUser scope
            if ($Type -eq "Msi") {
                Write-Progress -Activity "Installing SqlPackage" -Completed
                Stop-Function -Message "MSI installation is only supported on Windows. Use Zip type on Unix platforms."
                return
            }
            if ($Scope -eq "AllUsers") {
                Write-Progress -Activity "Installing SqlPackage" -Completed
                Stop-Function -Message "AllUsers scope is only supported on Windows. Use CurrentUser scope on Unix platforms."
                return
            }
        } else {
            # Windows-specific validations
            # Validate scope and type combination
            if ($Type -eq "Msi" -and $Scope -eq "CurrentUser") {
                Write-Progress -Activity "Installing SqlPackage" -Completed
                Stop-Function -Message "MSI installation is only supported for AllUsers scope. Use Zip type for CurrentUser scope."
                return
            }

            # Check for admin privileges when using MSI or AllUsers scope
            if ($Type -eq "Msi" -or $Scope -eq "AllUsers") {
                try {
                    $null = Test-ElevationRequirement -ComputerName $env:COMPUTERNAME -Continue
                } catch {
                    Write-Progress -Activity "Installing SqlPackage" -Completed
                    Stop-Function -Message "MSI installation and AllUsers scope require administrative privileges. Please run as administrator or use CurrentUser scope with Zip type."
                    return
                }
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        Write-Progress -Activity "Installing SqlPackage" -Status "Checking for existing installation..." -PercentComplete 15

        # Check if SqlPackage already exists
        if (-not $LocalFile.StartsWith("http") -and -not (Test-Path -Path $LocalFile) -and -not $Force) {
            if (-not (Test-Path -Path $localCachedCopy)) {
                Write-Message -Level Verbose -Message "No local file exists. Downloading now."
                if ((Test-Path -Path $localCachedCopy) -and (Test-Path -Path $Path) -and -not $Force) {
                    Write-Message -Level Warning -Message "SqlPackage already exists at $Path. Skipping download. Use -Force to overwrite."
                    Write-Progress -Activity "Installing SqlPackage" -Completed
                    return
                }
            }
        }

        if (-not $LocalFile.StartsWith("http") -and (Test-Path -Path $localCachedCopy) -and (Test-Path -Path $Path) -and -not $Force) {
            Write-Message -Level Verbose -Message "SqlPackage already exists at $Path. Skipping download."
            Write-Message -Level Verbose -Message "Use -Force to overwrite."
            Write-Progress -Activity "Installing SqlPackage" -Completed
            return
        }

        # Download if needed
        if ($LocalFile.StartsWith("http") -or -not (Test-Path -Path $LocalFile) -or $Force) {
            Write-Progress -Activity "Installing SqlPackage" -Status "Starting download from Microsoft..." -PercentComplete 20
            Write-Message -Level Verbose -Message "Downloading SqlPackage from $url"

            try {
                Write-Progress -Activity "Installing SqlPackage" -Status "Downloading SqlPackage package..." -PercentComplete 25
                try {
                    Invoke-TlsWebRequest -Uri $url -OutFile $LocalFile -UseBasicParsing
                } catch {
                    Write-Progress -Activity "Installing SqlPackage" -Status "Retrying download with proxy settings..." -PercentComplete 28
                    # Try with default proxy and usersettings
                    (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                    Invoke-TlsWebRequest -Uri $url -OutFile $LocalFile -UseBasicParsing
                }
                Write-Progress -Activity "Installing SqlPackage" -Status "Download completed successfully" -PercentComplete 45
            } catch {
                Write-Progress -Activity "Installing SqlPackage" -Completed
                Stop-Function -Message "Couldn't download SqlPackage. Download failed: $_" -ErrorRecord $_
                return
            }
        }

        Write-Progress -Activity "Installing SqlPackage" -Status "Preparing installation..." -PercentComplete 50

        # Install SqlPackage
        if ($Pscmdlet.ShouldProcess("$LocalFile", "Install SqlPackage")) {
            if ($LocalFile.StartsWith("http")) {
                Write-Progress -Activity "Installing SqlPackage" -Completed
                Stop-Function -Message "LocalFile cannot be a URL. It must be a local file path."
                return
            }

            if (-not (Test-Path -Path $LocalFile)) {
                Write-Progress -Activity "Installing SqlPackage" -Completed
                Stop-Function -Message "LocalFile $LocalFile does not exist."
                return
            }

            if ($LocalFile.EndsWith(".msi") -or $Type -eq "Msi") {
                Write-Progress -Activity "Installing SqlPackage" -Status "Installing MSI package..." -PercentComplete 70
                Write-Message -Level Verbose -Message "Installing SqlPackage MSI for AllUsers scope"

                $msiArgs = @(
                    "/i `"$LocalFile`""
                    "/quiet"
                    "/qn"
                    "/norestart"
                )
                $msiArguments = $msiArgs -join " "
                Write-Message -Level Verbose -Message "Installing SqlPackage from $LocalFile"
                $process = Start-Process -FilePath msiexec -ArgumentList $msiArguments -Wait -PassThru
                if ($process.ExitCode -ne 0) {
                    Write-Progress -Activity "Installing SqlPackage" -Completed
                    Stop-Function -Message "Failed to install SqlPackage from $LocalFile. Exit code: $($process.ExitCode)"
                    return
                }
            } else {
                Write-Progress -Activity "Installing SqlPackage" -Status "Extracting ZIP archive..." -PercentComplete 70
                Write-Message -Level Verbose -Message "Extracting SqlPackage zip to $Path"
                if (-not (Test-Path -Path $Path)) {
                    $null = New-Item -ItemType Directory -Path $Path -Force
                }
                # Remove existing files if Force is specified
                if ($Force -and (Test-Path -Path $Path)) {
                    Remove-Item -Path "$Path\*" -Recurse -Force -ErrorAction SilentlyContinue
                }

                # Unpack archive
                try {
                    Expand-Archive -Path $LocalFile -DestinationPath $Path -Force:$Force

                    # Make executable on Unix platforms
                    if ($PSVersionTable.Platform -eq "Unix") {
                        $executablePath = Join-Path $Path "sqlpackage"
                        if (Test-Path $executablePath) {
                            try {
                                & chmod "+x" $executablePath 2>$null
                            } catch {
                                Write-Message -Level Warning -Message "Could not make sqlpackage executable. You may need to run 'chmod +x $executablePath' manually."
                            }
                        }
                    }
                } catch {
                    Write-Progress -Activity "Installing SqlPackage" -Completed
                    Stop-Function -Message "Unable to extract SqlPackage to $Path. $_" -ErrorRecord $_
                    return
                }
            }
        }

        Write-Progress -Activity "Installing SqlPackage" -Status "Verifying installation..." -PercentComplete 90

        # Verify installation
        if ($PSVersionTable.Platform -eq "Unix") {
            $sqlPackagePaths = @(
                "$Path/sqlpackage"
            )
        } else {
            $sqlPackagePaths = @(
                "$Path\SqlPackage.exe"
                "${env:ProgramFiles}\Microsoft SQL Server\*\DAC\bin\SqlPackage.exe"
            )
        }

        $sqlPackageFound = $false
        $installedPath = $null
        foreach ($sqlPath in $sqlPackagePaths) {
            if (Test-Path -Path $sqlPath) {
                $sqlPackageFound = $true
                $installedPath = $sqlPath
                Write-Message -Level Verbose -Message "SqlPackage found at: $sqlPath"
                break
            }
        }

        Write-Progress -Activity "Installing SqlPackage" -Status "Installation completed!" -PercentComplete 100
        Start-Sleep -Milliseconds 500
        Write-Progress -Activity "Installing SqlPackage" -Completed

        if ($sqlPackageFound) {
            Write-Message -Level Verbose -Message "SqlPackage installed successfully"
            # Return the installation information
            [PSCustomObject]@{
                Name      = if ($PSVersionTable.Platform -eq "Unix") { "sqlpackage" } else { "SqlPackage.exe" }
                Path      = $installedPath
                Installed = $true
            }
        } else {
            Stop-Function -Message "SqlPackage installation failed - SqlPackage.exe not found in expected locations"
        }
    }
}
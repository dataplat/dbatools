function Get-DbaSqlPackagePath {
    <#
    .SYNOPSIS
        Gets the path to SqlPackage.exe, checking installed versions and bundled versions.

    .DESCRIPTION
        This function implements the logic to find SqlPackage.exe by:
        1. First checking if SqlPackage is available via Get-Command (system PATH)
        2. Then checking the dbatools data directory (installed via Install-DbaSqlPackage)
        3. Then checking the bundled version in the dbatools library
        4. If not found, suggesting to use Install-DbaSqlPackage to install it

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SqlPackage, DacPac, Deployment
        Author: dbatools team

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        System.String. The path to SqlPackage.exe if found, otherwise $null.
    #>
    [CmdletBinding()]
    param (
        [switch]$EnableException
    )

    # Determine executable name based on platform
    if ($PSVersionTable.Platform -eq "Unix") {
        $executableName = "sqlpackage"
    } else {
        $executableName = "SqlPackage"
    }

    # First try to find SqlPackage using Get-Command (system PATH)
    try {
        $sqlPackageCommand = Get-Command -Name $executableName -ErrorAction SilentlyContinue
        if ($sqlPackageCommand) {
            Write-Message -Level Verbose -Message "Found $executableName in system PATH at: $($sqlPackageCommand.Source)"
            return $sqlPackageCommand.Source
        }
    } catch {
        Write-Message -Level Verbose -Message "Error checking for system-installed SqlPackage: $($_.Exception.Message)"
    }

    # Second, try the dbatools data directory (installed via Install-DbaSqlPackage)
    $dbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"
    # Normalize path to remove any trailing slashes before joining
    $dbatoolsData = $dbatoolsData.TrimEnd('/', '\')

    if ($PSVersionTable.Platform -eq "Unix") {
        $installedExe = Join-Path -Path $dbatoolsData -ChildPath "sqlpackage" | Join-Path -ChildPath "sqlpackage"
    } else {
        $installedExe = Join-Path -Path $dbatoolsData -ChildPath "sqlpackage" | Join-Path -ChildPath "SqlPackage.exe"
    }

    if (Test-Path -Path $installedExe) {
        Write-Message -Level Verbose -Message "Found $executableName in dbatools data directory at: $installedExe"
        return $installedExe
    }

    # Third, try the bundled version (legacy path for backwards compatibility)
    if ($PSVersionTable.Platform -eq "Unix") {
        $bundledExe = Join-Path -Path $script:PSModuleRoot -ChildPath "bin" | Join-Path -ChildPath "sqlpackage" | Join-Path -ChildPath "sqlpackage"
    } else {
        $bundledExe = Join-Path -Path $script:PSModuleRoot -ChildPath "bin" | Join-Path -ChildPath "sqlpackage" | Join-Path -ChildPath "SqlPackage.exe"
    }

    if (Test-Path -Path $bundledExe) {
        Write-Message -Level Verbose -Message "Found bundled $executableName at: $bundledExe"
        return $bundledExe
    }

    # Fourth, check common installation paths (platform-specific)
    if ($PSVersionTable.Platform -eq "Unix") {
        $commonPaths = @(
            "/usr/local/sqlpackage/sqlpackage",
            "/opt/sqlpackage/sqlpackage"
        )
    } else {
        $commonPaths = @(
            "${env:ProgramFiles}\Microsoft SQL Server\*\DAC\bin\SqlPackage.exe",
            "${env:ProgramFiles(x86)}\Microsoft SQL Server\*\DAC\bin\SqlPackage.exe"
        )
    }

    foreach ($pathPattern in $commonPaths) {
        if ($pathPattern -like "*\**") {
            # Handle wildcard patterns (Windows only)
            $foundPaths = Get-ChildItem -Path $pathPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
            if ($foundPaths) {
                $newestPath = $foundPaths[0].FullName
                Write-Message -Level Verbose -Message "Found system-installed $executableName at: $newestPath"
                return $newestPath
            }
        } else {
            # Handle direct paths (Unix)
            if (Test-Path -Path $pathPattern) {
                Write-Message -Level Verbose -Message "Found system-installed $executableName at: $pathPattern"
                return $pathPattern
            }
        }
    }

    # If we get here, SqlPackage was not found
    $message = @"
Could not find SqlPackage. SqlPackage is required for DAC operations.

To install SqlPackage, use:
    Install-DbaSqlPackage

This will download and install SqlPackage to your dbatools data directory, making it available for use with dbatools DAC commands.
"@

    if ($EnableException) {
        Stop-Function -Message $message -Target "SqlPackage"
        throw "SqlPackage not found"
    } else {
        Stop-Function -Message $message -Target "SqlPackage"
        return $null
    }
}
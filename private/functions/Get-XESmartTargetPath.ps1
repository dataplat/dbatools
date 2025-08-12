function Get-XESmartTargetPath {
    <#
    .SYNOPSIS
        Gets the path to XESmartTarget.Core.dll, checking installed versions and bundled legacy versions.

    .DESCRIPTION
        This function implements the logic to find XESmartTarget.Core.dll by:
        1. First checking the dbatools data directory (installed via Install-DbaXESmartTarget)
        2. Then checking the bundled version in the dbatools library (legacy)
        3. If not found, checking if XESmartTarget is installed via Get-Command
        4. If found, looking for the DLL in the same directory as the executable
        5. If not found, suggesting to use Install-DbaXESmartTarget to install it

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvent, XE, XEvent, SmartTarget
        Author: dbatools team

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        System.String. The path to XESmartTarget.Core.dll if found, otherwise $null.
    #>
    [CmdletBinding()]
    param (
        [switch]$EnableException
    )

    # First try the dbatools data directory (installed via Install-DbaXESmartTarget)
    $dbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"
    $installedDll = Join-DbaPath -Path $dbatoolsData -ChildPath "XESmartTarget", "XESmartTarget.Core.dll"
    if (Test-Path -Path $installedDll) {
        Write-Message -Level Verbose -Message "Found XESmartTarget.Core.dll in dbatools data directory at: $installedDll"
        return $installedDll
    }

    # Second, try the bundled version (legacy path for backwards compatibility)
    $bundledDll = Join-DbaPath -Path $script:libraryroot -ChildPath "third-party", "XESmartTarget", "XESmartTarget.Core.dll"
    if (Test-Path -Path $bundledDll) {
        Write-Message -Level Verbose -Message "Found bundled XESmartTarget.Core.dll at: $bundledDll"
        return $bundledDll
    }

    # Third, check if XESmartTarget is installed system-wide via Get-Command
    try {
        $xeCommand = Get-Command -Name "XESmartTarget" -ErrorAction SilentlyContinue
        if ($xeCommand) {
            # Get the directory where the executable is located
            $xeDirectory = Split-Path -Parent $xeCommand.Source
            $systemInstalledDll = Join-Path -Path $xeDirectory -ChildPath "XESmartTarget.Core.dll"

            if (Test-Path -Path $systemInstalledDll) {
                Write-Message -Level Verbose -Message "Found system-installed XESmartTarget.Core.dll at: $systemInstalledDll"
                return $systemInstalledDll
            } else {
                Write-Message -Level Warning -Message "Found XESmartTarget executable at '$($xeCommand.Source)' but could not find XESmartTarget.Core.dll in the same directory."
            }
        }
    } catch {
        Write-Message -Level Verbose -Message "Error checking for system-installed XESmartTarget: $($_.Exception.Message)"
    }

    # If we get here, XESmartTarget.Core.dll was not found
    $message = @"
Could not find XESmartTarget.Core.dll. XESmartTarget is no longer bundled with dbatools.

To install XESmartTarget, use:
    Save-DbaCommunitySoftware -Software XESmartTarget

This will download and install XESmartTarget to your dbatools data directory, making it available for use with dbatools XE commands.
"@

    if ($EnableException) {
        Stop-Function -Message $message -Target "XESmartTarget"
        throw "XESmartTarget.Core.dll not found"
    } else {
        Stop-Function -Message $message -Target "XESmartTarget"
        return $null
    }
}
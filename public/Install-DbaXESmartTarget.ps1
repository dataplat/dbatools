function Install-DbaXESmartTarget {
    <#
    .SYNOPSIS
        Downloads and installs XESmartTarget for use with dbatools Extended Events commands.

    .DESCRIPTION
        Downloads and installs XESmartTarget from GitHub to the dbatools data directory.
        XESmartTarget is required for certain Extended Events functionality in dbatools.

        This command downloads XESmartTarget to the user's dbatools data directory, making it
        available for Extended Events commands that require XESmartTarget.Core.dll.

    .PARAMETER LocalFile
        Specifies the path to a local XESmartTarget zip file to install from instead of downloading from GitHub.
        This can be useful for offline installations or when you have a specific version.

    .PARAMETER Force
        If this switch is enabled, any existing XESmartTarget installation will be overwritten.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvent, XE, XEvent, SmartTarget, Install
        Author: dbatools team

        Website: https://dbatools.io
        Copyright: (c) 2024 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Install-DbaXESmartTarget

    .EXAMPLE
        PS C:\> Install-DbaXESmartTarget

        Downloads and installs the latest version of XESmartTarget from GitHub.

    .EXAMPLE
        PS C:\> Install-DbaXESmartTarget -LocalFile "C:\Downloads\XESmartTarget.zip"

        Installs XESmartTarget from a local zip file.

    .EXAMPLE
        PS C:\> Install-DbaXESmartTarget -Force

        Downloads and installs XESmartTarget, overwriting any existing installation.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [string]$LocalFile,
        [switch]$Force,
        [switch]$EnableException
    )

    process {
        # Check if XESmartTarget is already installed (unless -Force is specified)
        if (-not $Force) {
            $existingPath = Get-XESmartTargetPath
            if ($existingPath) {
                Write-Message -Level Host -Message "XESmartTarget is already installed at: $existingPath"
                Write-Message -Level Host -Message "Use -Force to reinstall or overwrite the existing installation."
                return
            }
        }

        # Get the dbatools data directory where we'll install XESmartTarget
        $dbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"
        $xeSmartTargetPath = Join-DbaPath -Path $dbatoolsData -Child "XESmartTarget"

        Write-Message -Level Host -Message "Installing XESmartTarget to: $xeSmartTargetPath"

        # Prepare parameters for Save-DbaCommunitySoftware
        $saveParams = @{
            Software        = 'XESmartTarget'
            EnableException = $EnableException
        }

        # Add LocalFile parameter if specified
        if ($LocalFile) {
            if (-not (Test-Path $LocalFile)) {
                Stop-Function -Message "Local file not found: $LocalFile" -Target $LocalFile
                return
            }
            $saveParams['LocalFile'] = $LocalFile
        }

        # Override the default LocalDirectory to use our desired path
        $saveParams['LocalDirectory'] = $xeSmartTargetPath

        if ($PSCmdlet.ShouldProcess("XESmartTarget", "Download and install to $xeSmartTargetPath")) {
            try {
                # Use Save-DbaCommunitySoftware to download and extract XESmartTarget
                Save-DbaCommunitySoftware @saveParams

                # Verify the installation by checking for the core DLL
                $coreDllPath = Join-DbaPath -Path $xeSmartTargetPath -Child "XESmartTarget.Core.dll"
                if (Test-Path $coreDllPath) {
                    Write-Message -Level Host -Message "XESmartTarget successfully installed!"
                    Write-Message -Level Host -Message "XESmartTarget.Core.dll found at: $coreDllPath"

                    # Return installation details
                    [PSCustomObject]@{
                        Software    = "XESmartTarget"
                        InstallPath = $xeSmartTargetPath
                        CoreDllPath = $coreDllPath
                        Status      = "Successfully Installed"
                    }
                } else {
                    Stop-Function -Message "Installation completed but XESmartTarget.Core.dll not found at expected location: $coreDllPath" -Target $coreDllPath
                    return
                }
            } catch {
                Stop-Function -Message "Failed to install XESmartTarget: $($_.Exception.Message)" -Target "XESmartTarget" -ErrorRecord $_
                return
            }
        }
    }
}
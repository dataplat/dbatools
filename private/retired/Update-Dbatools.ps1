function Update-Dbatools {
    <#
    .SYNOPSIS
        Updates the dbatools PowerShell module to the latest version

    .DESCRIPTION
        Updates the dbatools module by removing the current installation and replacing it with the latest version from PowerShell Gallery or GitHub. This function has been deprecated in favor of PowerShell's native Install-Module and Update-Module commands which provide better dependency management and version control.

    .PARAMETER Development
        Installs the latest development branch from GitHub instead of the stable release from PowerShell Gallery. Use this when you need access to the newest features or bug fixes that haven't been officially released yet. Development builds may contain untested changes, so avoid using this in production environments unless specifically needed for troubleshooting or testing.

    .PARAMETER Cleanup
        Removes previous versions of dbatools after installing the new version to free up disk space and avoid version conflicts. Use this when you have multiple dbatools versions installed and want to keep only the latest version. Without this switch, old versions remain on the system which can occasionally cause module loading issues or consume unnecessary disk space.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Module
        Author: Shawn Melton (@wsmelton), wsmelton.github.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Update-Dbatools

    .OUTPUTS
        None

        This command is deprecated and returns no output. It displays a warning message to console directing users to use PowerShell's built-in Install-Module and Update-Module commands instead. No pipeline objects are generated.

    .EXAMPLE
        PS C:\> Update-Dbatools

        Updates dbatools. Deletes current copy and replaces it with freshest copy.

    .EXAMPLE
        PS C:\> Update-Dbatools -dev

        Updates dbatools to the current development branch. Deletes current copy and replaces it with latest from github.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "It is the proper noun of the cmdlet")]
    param(
        [Alias("dev", "devbranch")]
        [switch]$Development,
        [switch]$Cleanup,
        [switch]$EnableException
    )
    Write-Warning "This command is deprecated. Please use PowerShell's built-in commands, Install-Module and Update-Module, instead."
}
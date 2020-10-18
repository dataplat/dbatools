function Update-Dbatools {
    <#
    .SYNOPSIS
        Exported function. Updates dbatools. Deletes current copy and replaces it with freshest copy.

    .DESCRIPTION
        Exported function. Updates dbatools. Deletes current copy and replaces it with freshest copy.

    .PARAMETER Development
        If this switch is enabled, the current development branch will be installed. By default, the latest official release is installed.

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
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Update-Dbatools

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
        [switch]$EnableException
    )
    $MyModuleBase = [SqlCollaborative.Dbatools.dbaSystem.SystemHost]::ModuleBase
    $InstallScript = Join-Path -path $MyModuleBase -ChildPath "install.ps1";
    if ($Development) {
        Write-Message -Level Verbose -Message "Installing dev/beta channel via $Installscript.";
        if ($PSCmdlet.ShouldProcess("development branch", "Updating dbatools")) {
            & $InstallScript -beta;
        }
    } else {
        Write-Message -Level Verbose -Message "Installing release version via $Installscript."
        if ($PSCmdlet.ShouldProcess("release branch", "Updating dbatools")) {
            & $InstallScript;
        }
    }
}
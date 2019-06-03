function Update-DbatoolsRemote {
    <#
    .SYNOPSIS
        Copy dbatools module to remote servers without internet connectivity.

    .DESCRIPTION
        This function will take and copy the dbatools module files from the local workstation and put them on a remote server/workstation without internet connection.

    .PARAMETER Destination
        The computer to copy the module files to.

    .PARAMETER Version
        Copy a specific version to the destination server.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted to choose to override files/folders that already exist on the destiantion.

    .NOTES
        Tags: Module
        Author: Garry Bargsley (@gbargsley), garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Update-DbatoolsRemote

    .EXAMPLE
        PS C:\> Update-DbatoolsRemote -Destination Server2

        Updates the dbatools module files to the latest version on the source system.

    .EXAMPLE
        PS C:\> Update-Dbatools -Version 0.9.791

        Updates dbatools to the specified version.

    #>
    [cmdletbinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [object[]]$Version,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
    }
    process {
    }
    end {
    }
}
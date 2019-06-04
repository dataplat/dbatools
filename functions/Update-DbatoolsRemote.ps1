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

    .NOTES
        Tags: Module
        Author: Garry Bargsley (@gbargsley), garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Update-DbatoolsRemote

    .EXAMPLE
        PS C:\> Update-DbatoolsRemote -Destination Server2, Server3

        Updates the dbatools module files on one or many destination servers to the latest version from the source system.

    .EXAMPLE
        PS C:\> Update-Dbatools -Destination Server2 -Version 0.9.791

        Updates dbatools to the specified version on the destination server.

    #>
    [cmdletbinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
    param (
        [parameter(Mandatory)]
        [object[]]$Destination,
        [string]$Version,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {

        $InstalledVersion = Get-Module dbatools -ListAvailable | Select-Object Version, ModuleBase

        foreach ( $DestInstance in $Destination ) {
            $DestinationPath = "\\$destinstance\C$\Program Files\WindowsPowerShell\Modules\dbatools\"

            try {
                If ( $Version -ne '' ) {
                    If ($InstalledVersion.Version -contains $Version) {
                        try {
                            $InstalledVersion = $InstalledVersion | Where-Object Version -EQ "$Version"
                            Copy-Item -Path $InstalledVersion.ModuleBase -Destination $DestinationPath -Recurse -Force
                        } catch {
                            Stop-Function -Message "There was an error copying files to the $DestInstance server for version $Version."
                            return
                        }
                    } Else {
                        Stop-Function -Message "The Version entered does not exist on $env:ComputerName."
                        return
                    }
                } Else {
                    $InstalledVersion = Get-Module dbatools -ListAvailable | Sort-Object Version -Descending | Select-Object Version, ModuleBase -First 1
                    If (Test-Path $InstalledVersion.ModuleBase) {
                        If (Test-Path $DestinationPath) {
                            try {
                                Copy-Item -Path $InstalledVersion.ModuleBase -Destination $DestinationPath -Recurse -Force
                            } catch {
                                Stop-Function -Message "There was an error copying files to the $DestInstance."
                                return
                            }
                        }
                    }
                }
            } catch {
                Stop-Function -Message "Error occurred while copying files to $DestInstance" -Category ConnectionError -ErrorRecord $_ -Target $DestInstance -Continue
            }
            Write-Output "dbatools version: $($InstalledVersion.Version) files have been copied to server $DestInstance"
        }
    }
}

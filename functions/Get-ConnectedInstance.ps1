function Get-ConnectedInstance {
    <#
    .SYNOPSIS
        Get a list of all connected instances.

    .DESCRIPTION
        Get a list of all connected instances

    .NOTES
        Tags: Connection
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-ConnectedInstance

    .EXAMPLE
        PS C:\> Get-ConnectedInstance

        Gets all connections

    #>
    [CmdletBinding()]
    param ()
    process {
        $global:connectionhash
    }
}
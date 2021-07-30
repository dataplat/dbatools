function Get-DbaConnectedInstance {
    <#
    .SYNOPSIS
        Get a list of all connected instances

    .DESCRIPTION
        Get a list of all connected instances

    .NOTES
        Tags: Connection
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaConnectedInstance

    .EXAMPLE
        PS C:\> Get-DbaConnectedInstance

        Gets all connected SQL Server instances

    #>
    [CmdletBinding()]
    param ()
    process {
        foreach ($key in $script:connectionhash.Keys) {
            [pscustomobject]@{
                SqlInstance      = [dbainstanceparameter]$key
                ConnectionString = (Hide-ConnectionString -ConnectionString $key)
                ConnectionObject = $script:connectionhash[$key]
                ConnectionType   = $script:connectionhash[$key].GetType().FullName
            }
        }
    }
}
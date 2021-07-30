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

    .EXAMPLE
        PS C:\> Get-DbaConnectedInstance | Select *

        Gets all connected SQL Server instances and shows the associated connectionstrings as well

    #>
    [CmdletBinding()]
    param ()
    process {
        foreach ($key in $script:connectionhash.Keys) {
            if ($script:connectionhash[$key].DataSource) {
                $instance = $script:connectionhash[$key] | Select-Object -First 1 -ExpandProperty DataSource
            } else {
                $instance = $script:connectionhash[$key] | Select-Object -First 1 -ExpandProperty Name
            }
            [pscustomobject]@{
                SqlInstance      = $instance
                ConnectionObject = $script:connectionhash[$key]
                ConnectionType   = $script:connectionhash[$key][0].GetType().FullName
                ConnectionString = (Hide-ConnectionString -ConnectionString $key)
            } | Select-DefaultView -Property SqlInstance, ConnectionType, ConnectionObject
        }
    }
}
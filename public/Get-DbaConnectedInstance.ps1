function Get-DbaConnectedInstance {
    <#
    .SYNOPSIS
        Returns SQL Server instances currently cached in the dbatools connection pool

    .DESCRIPTION
        Shows all SQL Server connections that are currently active or cached in your PowerShell session. When you connect to instances using dbatools commands like Connect-DbaInstance, those connections are stored in an internal cache for reuse. This command reveals what's in that cache, including connection details like whether pooling is enabled and the connection type (SMO server objects vs raw SqlConnection objects). Use this to track active connections before cleaning them up with Disconnect-DbaInstance or to troubleshoot connection-related issues in long-running scripts.

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
            $value = $script:connectionhash[$key] | Select-Object -First 1
            if ($value.ConnectionContext.NonPooledConnection -or $value.NonPooledConnection) {
                $pooling = $false
            } else {
                $pooling = $true
            }
            [PSCustomObject]@{
                SqlInstance      = $instance
                ConnectionObject = $script:connectionhash[$key]
                ConnectionType   = $value.GetType().FullName
                Pooled           = $pooling
                ConnectionString = (Hide-ConnectionString -ConnectionString $key)
            } | Select-DefaultView -Property SqlInstance, ConnectionType, ConnectionObject, Pooled
        }
    }
}
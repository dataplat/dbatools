function Get-DbaRunspace {
    <#
    .SYNOPSIS
        Returns registered runspaces.

    .DESCRIPTION
        Returns a list of runspaces that have been registered with dbatools

    .PARAMETER Name
        Default: "*"
        Only registered runspaces of similar names are returned.

    .EXAMPLE
        PS C:\> Get-DbaRunspace

        Returns all registered runspaces

    .EXAMPLE
        PS C:\> Get-DbaRunspace -Name 'mymodule.maintenance'

        Returns the runspace registered under the name 'mymodule.maintenance'
    #>
    [CmdletBinding()]
    param (
        [string]
        $Name = "*"
    )

    [Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces.Values | Where-Object Name -Like $Name
}
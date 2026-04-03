function Get-DbaInstanceList {
    <#
    .SYNOPSIS
        Returns the user-maintained list of SQL Server instances used for tab completion.

    .DESCRIPTION
        Returns all SQL Server instance names from the user-maintained list that is pre-loaded
        into the dbatools tab completion cache for the -SqlInstance parameter. This list allows
        users to have their frequently used instances available for autocomplete in their
        PowerShell terminal without needing to connect to them first.

        Use Add-DbaInstanceList to add instances to the list and Remove-DbaInstanceList to
        remove them.

        Instances can also be pre-loaded at module import time by setting the
        $env:DBATOOLS_KNOWN_INSTANCES environment variable to a comma-separated list of instance
        names in your PowerShell profile.

    .OUTPUTS
        System.String

        Returns instance names as strings. Each instance name in the user-maintained
        autocomplete list is returned as a separate string object.

    .NOTES
        Tags: TabCompletion, Autocomplete
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaInstanceList

    .EXAMPLE
        PS C:\> Get-DbaInstanceList

        Returns all instance names from the user-maintained autocomplete list.

    .EXAMPLE
        PS C:\> Get-DbaInstanceList | Remove-DbaInstanceList

        Removes all instances from the user-maintained autocomplete list.
    #>
    [CmdletBinding()]
    param ()

    process {
        Get-DbatoolsConfigValue -FullName "TabExpansion.KnownInstances" -Fallback @()
    }
}

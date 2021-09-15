function Add-TeppCacheItem {
    <#
    .SYNOPSIS
        Internal function to add an item to the TEPP cache.

    .DESCRIPTION
        Internal function to add an item to the TEPP cache.

    .PARAMETER SqlInstance
        The SQL Server instance.

    .PARAMETER Type
        The type of object. Must be part of "[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache.Keys".

    .PARAMETER Name
        The name of the object that should be added to the cache. Will not be added if already in cache.

    .EXAMPLE
        Add-TeppCacheItem -SqlInstance $server -Type database -Name AdventureWorks

        Adds an entry for the database AdventureWorks in the TEPP cache.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [Parameter(Mandatory)]
        [string]$Type,
        [Parameter(Mandatory)]
        [string]$Name
    )
    try {
        if ($SqlInstance.InputObject.GetType().Name -eq 'Server') {
            $serverName = $SqlInstance.InputObject.Name.ToLowerInvariant()
        } else {
            $serverName = $SqlInstance.FullSmoName
        }
        if ($serverName -in [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache[$Type].Keys) {
            if ($Name -notin [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache[$Type][$serverName]) {
                [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache[$Type][$serverName] = @([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache[$Type][$serverName]) + $Name | Sort-Object
                Write-Message -Level Debug -Message "$Name added to cache for $Type on $serverName."
            } else {
                Write-Message -Level Debug -Message "$Name already in cache for $Type on $serverName."
            }
        } else {
            Write-Message -Level Debug -Message "No cache for $serverName found."
        }
    } catch {
        Write-Message -Level Debug -Message "Failed to add $Name to cache for $Type on $serverName. $_"
    }
}
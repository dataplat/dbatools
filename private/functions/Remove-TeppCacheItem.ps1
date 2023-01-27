function Remove-TeppCacheItem {
    <#
    .SYNOPSIS
        Internal function to remove an item from the TEPP cache.

    .DESCRIPTION
        Internal function to remove an item from the TEPP cache.

    .PARAMETER SqlInstance
        The SQL Server instance.

    .PARAMETER Type
        The type of object. Must be part of "[Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache.Keys".

    .PARAMETER Name
        The name of the object that should be removed from the cache.

    .EXAMPLE
        Remove-TeppCacheItem -SqlInstance $server -Type database -Name AdventureWorks

        Removes the entry for the database AdventureWorks from the TEPP cache.
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
        if ($serverName -in [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache[$Type].Keys) {
            if ($Name -in [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache[$Type][$serverName]) {
                [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache[$Type][$serverName] = [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache[$Type][$serverName] | Where-Object { $_ -ne $Name }
                Write-Message -Level Debug -Message "$Name removed from cache for $Type on $serverName."
            } else {
                Write-Message -Level Debug -Message "$Name not found in cache for $Type on $serverName."
            }
        } else {
            Write-Message -Level Debug -Message "No cache for $serverName found."
        }
    } catch {
        Write-Message -Level Debug -Message "Failed to remove $Name from cache for $Type on $serverName. $_"
    }
}
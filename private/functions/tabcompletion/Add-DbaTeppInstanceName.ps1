function Add-DbaTeppInstanceName {
    <#
    .SYNOPSIS
        Adds instance names to the tab completion cache for -SqlInstance, keeping the cache an array.

    .DESCRIPTION
        The cache [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] starts as $null.
        Appending to it with += turned it into a string, after which += concatenated every further name
        onto that string and -notcontains compared the whole string, so every later connection appended
        its name again and the completer offered one long blob. This function rebuilds the cache as an
        array every time, lower cases the names like the completer expects, and skips duplicates.

    .PARAMETER Name
        The instance names to add. Empty entries are ignored.

    .EXAMPLE
        PS C:\> Add-DbaTeppInstanceName -Name $instance.FullSmoName

        Adds the instance to the completion cache of the current session.
    #>
    [CmdletBinding()]
    param (
        [AllowEmptyString()]
        [AllowNull()]
        [string[]]$Name
    )

    $knownInstances = @([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] | Where-Object { $PSItem })
    foreach ($item in $Name) {
        if (-not $item) {
            continue
        }
        $lower = $item.Trim().ToLowerInvariant()
        if ($lower -and $knownInstances -notcontains $lower) {
            $knownInstances += $lower
        }
    }
    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] = $knownInstances
}

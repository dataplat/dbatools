function Remove-DbaInstanceList {
    <#
    .SYNOPSIS
        Removes one or more SQL Server instances from the user-maintained autocomplete list.

    .DESCRIPTION
        Removes SQL Server instance names from the user-maintained list that is pre-loaded into
        the dbatools tab completion cache for the -SqlInstance parameter. The instances are
        removed from the stored configuration and from the current session's autocomplete cache.

        Use Add-DbaInstanceList to add instances to the list and Get-DbaInstanceList to view
        the current list.

    .PARAMETER SqlInstance
        The SQL Server instance name or names to remove from the autocomplete list.
        Accepts pipeline input.

    .PARAMETER Register
        Persists the updated instance list to disk after removal so the change is available in
        future PowerShell sessions. Without this switch, the removal only affects the stored
        configuration for the current session.

    .PARAMETER Scope
        Determines where the persistent configuration is stored when using -Register.
        UserDefault stores the setting for the current user only.

    .OUTPUTS
        None

        This command updates the stored configuration but does not output any objects to the
        pipeline. Use Get-DbaInstanceList to retrieve the current configured instance names.

    .NOTES
        Tags: TabCompletion, Autocomplete
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaInstanceList

    .EXAMPLE
        PS C:\> Remove-DbaInstanceList -SqlInstance "sql01"

        Removes sql01 from the autocomplete instance list.

    .EXAMPLE
        PS C:\> Remove-DbaInstanceList -SqlInstance "sql01", "sql02\dev" -Register

        Removes two instances from the list and persists the change across PowerShell sessions.

    .EXAMPLE
        PS C:\> Get-DbaInstanceList | Remove-DbaInstanceList -Register

        Removes all instances from the user-maintained autocomplete list and persists the change.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$SqlInstance,
        [switch]$Register,
        [Dataplat.Dbatools.Configuration.ConfigScope]$Scope = [Dataplat.Dbatools.Configuration.ConfigScope]::UserDefault
    )

    begin {
        $current = @(Get-DbatoolsConfigValue -FullName "TabExpansion.KnownInstances" -Fallback @())
        $toRemove = @()
    }

    process {
        foreach ($instance in $SqlInstance) {
            $lower = $instance.Trim().ToLowerInvariant()
            if (-not $lower) { continue }
            if ($toRemove -notcontains $lower) {
                $toRemove += $lower
            }
        }
    }

    end {
        if ($toRemove.Count -gt 0) {
            if ($PSCmdlet.ShouldProcess("instance list", "Remove $($toRemove -join ', ')")) {
                $updated = $current | Where-Object { $toRemove -notcontains $_ }
                if ($null -eq $updated) { $updated = @() }
                Set-DbatoolsConfig -FullName "TabExpansion.KnownInstances" -Value @($updated)

                $cache = @([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"])
                if ($cache.Count -gt 0) {
                    $cache = $cache | Where-Object { $toRemove -notcontains $_ }
                    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] = @($cache)
                }

                if ($Register) {
                    Register-DbatoolsConfig -FullName "TabExpansion.KnownInstances" -Scope $Scope
                }
            }
        }
    }
}

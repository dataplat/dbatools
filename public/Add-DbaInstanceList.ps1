function Add-DbaInstanceList {
    <#
    .SYNOPSIS
        Adds one or more SQL Server instances to the user-maintained autocomplete list.

    .DESCRIPTION
        Adds SQL Server instance names to a persistent list that pre-populates the tab completion
        cache for the -SqlInstance parameter across all dbatools commands. This allows users to
        have their frequently used instances available for autocomplete in their PowerShell
        terminal without needing to connect to them first.

        The instance list is stored using the dbatools configuration system. Use -Register to
        persist the list across PowerShell sessions.

        Instances can also be pre-loaded at module import time by setting the
        $env:DBATOOLS_KNOWN_INSTANCES environment variable to a comma-separated list of instance
        names in your PowerShell profile.

    .PARAMETER SqlInstance
        The SQL Server instance name or names to add to the autocomplete list.
        Accepts pipeline input.

    .PARAMETER Register
        Persists the instance list to disk so it is available in future PowerShell sessions.
        Without this switch, the list only exists for the current session.

    .PARAMETER Scope
        Determines where the persistent configuration is stored when using -Register.
        UserDefault stores the setting for the current user only.

    .OUTPUTS
        None

        This command updates the autocomplete cache but does not output any objects to the
        pipeline. Use Get-DbaInstanceList to retrieve the configured instance names.

    .NOTES
        Tags: TabCompletion, Autocomplete
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Add-DbaInstanceList

    .EXAMPLE
        PS C:\> Add-DbaInstanceList -SqlInstance "sql01", "sql02\dev"

        Adds sql01 and sql02\dev to the autocomplete instance list for the current session.

    .EXAMPLE
        PS C:\> Add-DbaInstanceList -SqlInstance "sql01" -Register

        Adds sql01 to the autocomplete instance list and persists it across PowerShell sessions.

    .EXAMPLE
        PS C:\> "sql01", "sql02" | Add-DbaInstanceList -Register

        Adds two instances to the list via pipeline and persists them across sessions.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$SqlInstance,
        [switch]$Register,
        [Dataplat.Dbatools.Configuration.ConfigScope]$Scope = [Dataplat.Dbatools.Configuration.ConfigScope]::UserDefault
    )

    begin {
        $current = Get-DbatoolsConfigValue -FullName "TabExpansion.KnownInstances" -Fallback @()
        $toAdd = @()
    }

    process {
        foreach ($instance in $SqlInstance) {
            $lower = $instance.Trim().ToLowerInvariant()
            if (-not $lower) { continue }

            if ($current -notcontains $lower -and $toAdd -notcontains $lower) {
                $toAdd += $lower
            }

            # Update the TEPP cache immediately for this session
            if ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $lower) {
                [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $lower
            }
        }
    }

    end {
        if ($toAdd.Count -gt 0) {
            $combined = @($current) + @($toAdd)
            Set-DbatoolsConfig -FullName "TabExpansion.KnownInstances" -Value $combined
        }
        if ($Register) {
            Register-DbatoolsConfig -FullName "TabExpansion.KnownInstances" -Scope $Scope
        }
    }
}

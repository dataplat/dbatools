# Sets the default interval and timeout for TEPP updates
Set-DbatoolsConfig -FullName 'TabExpansion.UpdateInterval' -Value (New-TimeSpan -Minutes 3) -Initialize -Validation timespan -Handler { [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppUpdateInterval = $args[0] } -Description 'The frequency in which TEPP tries to update each cache for autocompletion'
Set-DbatoolsConfig -FullName 'TabExpansion.UpdateTimeout' -Value (New-TimeSpan -Seconds 30) -Initialize -Validation timespan -Handler { [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppUpdateTimeout = $args[0] } -Description 'After this timespan has passed without connections to a server, the TEPP updater will no longer update the cache.'

# Disable the management cache entire
Set-DbatoolsConfig -FullName 'TabExpansion.Disable' -Value $false -Initialize -Validation bool -Handler {
    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppDisabled = $args[0]

    # Disable Async TEPP runspace if not needed
    if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppAsyncDisabled -or [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppDisabled) {
        [Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces["dbatools-teppasynccache"].Stop()
    } else {
        [Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces["dbatools-teppasynccache"].Start()
    }
} -Description 'Globally disables all TEPP functionality by dbatools'
Set-DbatoolsConfig -FullName 'TabExpansion.Disable.Asynchronous' -Value $false -Initialize -Validation bool -Handler {
    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppAsyncDisabled = $args[0]

    # Disable Async TEPP runspace if not needed
    if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppAsyncDisabled -or [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppDisabled) {
        [Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces["dbatools-teppasynccache"].Stop()
    } else {
        [Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces["dbatools-teppasynccache"].Start()
    }
} -Description 'Globally disables asynchronous TEPP updates in the background'
Set-DbatoolsConfig -FullName 'TabExpansion.Disable.Synchronous' -Value $true -Initialize -Validation bool -Handler { [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled = $args[0] } -Description 'Globally disables synchronous TEPP updates, performed whenever connecting o the server. If this is not disabled, it will only perform updates that are fast to perform, in order to minimize performance impact. This may lead to some TEPP functionality loss if asynchronous updates are disabled.'
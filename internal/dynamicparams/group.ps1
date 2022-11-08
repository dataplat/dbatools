#region Initialize Cache
if (-not [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["group"]) {
    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["group"] = @{ }
}
#endregion Initialize Cache

#region Tepp Data return
$ScriptBlock = {
    param (
        $commandName,

        $parameterName,

        $wordToComplete,

        $commandAst,

        $fakeBoundParameter
    )


    $server = $fakeBoundParameter['SqlInstance']

    if (-not $server) {
        $server = $fakeBoundParameter['Source']
    }

    if (-not $server) {
        $server = $fakeBoundParameter['ComputerName']
    }

    if (-not $server) { return }

    try {
        [DbaInstanceParameter]$parServer = $server | Select-Object -First 1
    } catch {
        return
    }

    if ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["group"][$parServer.FullSmoName.ToLowerInvariant()]) {
        foreach ($name in ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["group"][$parServer.FullSmoName.ToLowerInvariant()] | Where-DbaObject -Like "$wordToComplete*")) {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        return
    }

    try {
        $serverObject = Connect-DbaInstance -SqlInstance $parServer -SqlCredential $fakeBoundParameter['SqlCredential'] -ErrorAction Stop
        foreach ($name in ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["group"][$parServer.FullSmoName.ToLowerInvariant()] | Where-DbaObject -Like "$wordToComplete*")) {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        return
    } catch {
        return
    }
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name Group
#endregion Tepp Data return

#region Update Cache
$ScriptBlock = {

    $cms = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($server.ConnectionContext.SqlConnectionObject)
    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["group"][$FullSmoName] = $cms.DatabaseEngineServerGroup.ServerGroups.Name
}
Register-DbaTeppInstanceCacheBuilder -ScriptBlock $ScriptBlock
#endregion Update Cache
#region Initialize Cache
if (-not [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["resourcepool"]) {
    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["resourcepool"] = @{ }
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

    if ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["resourcepool"][$parServer.FullSmoName.ToLowerInvariant()]) {
        foreach ($name in ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["resourcepool"][$parServer.FullSmoName.ToLowerInvariant()] | Where-DbaObject -Like "$wordToComplete*")) {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        return
    }

    try {
        $serverObject = Connect-DbaInstance -SqlInstance $parServer -SqlCredential $fakeBoundParameter['SqlCredential'] -ErrorAction Stop
        foreach ($name in ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["resourcepool"][$parServer.FullSmoName.ToLowerInvariant()] | Where-DbaObject -Like "$wordToComplete*")) {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        return
    } catch {
        return
    }
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name ResourcePool
#endregion Tepp Data return

#region Update Cache
$ScriptBlock = {

    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["resourcepool"][$FullSmoName] = ($server.ResourceGovernor.ResourcePools | Where-Object Name -NotIn 'internal', 'default').Name
}
Register-DbaTeppInstanceCacheBuilder -ScriptBlock $ScriptBlock
#endregion Update Cache
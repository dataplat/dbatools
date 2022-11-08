#region Initialize Cache
if (-not [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["instanceproperty"]) {
    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["instanceproperty"] = @{ }
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

    if ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["instanceproperty"][$parServer.FullSmoName.ToLowerInvariant()]) {
        foreach ($name in ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["instanceproperty"][$parServer.FullSmoName.ToLowerInvariant()] | Where-DbaObject -Like "$wordToComplete*")) {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        return
    }

    try {
        foreach ($name in ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["instanceproperty"][$parServer.FullSmoName.ToLowerInvariant()] | Where-DbaObject -Like "$wordToComplete*")) {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        return
    } catch {
        return
    }
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name InstanceProperty
#endregion Tepp Data return

#region Update Cache
$ScriptBlock = {
    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["instanceproperty"][$FullSmoName] = $server.Information.Properties.Name + $server.UserOptions.Properties.Name + $server.Settings.Properties.Name
}
Register-DbaTeppInstanceCacheBuilder -ScriptBlock $ScriptBlock
#endregion Update Cache
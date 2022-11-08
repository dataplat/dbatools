#region Initialize Cache
if (-not [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["configname"]) {
    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["configname"] = @{ }
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

    if ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["configname"][$parServer.FullSmoName.ToLowerInvariant()]) {
        foreach ($name in ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["configname"][$parServer.FullSmoName.ToLowerInvariant()] | Where-DbaObject -Like "$wordToComplete*")) {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        return
    }

    try {
        $serverObject = Connect-DbaInstance -SqlInstance $parServer -SqlCredential $fakeBoundParameter['SqlCredential'] -ErrorAction Stop
        foreach ($name in ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["configname"][$parServer.FullSmoName.ToLowerInvariant()] | Where-DbaObject -Like "$wordToComplete*")) {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        return
    } catch {
        return
    }
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name ConfigName
#endregion Tepp Data return

#region Update Cache
$ScriptBlock = {

    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["configname"][$FullSmoName] = (Get-Member -InputObject $server.Configuration -MemberType Property -Force | Where-Object Name -NotIn 'Parent',
        'Properties').Name
}
Register-DbaTeppInstanceCacheBuilder -ScriptBlock $ScriptBlock
#endregion Update Cache
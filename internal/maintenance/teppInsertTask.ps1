$scriptBlock = {
    $ModuleRoot = [Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleBase

    $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText((Resolve-Path "$ModuleRoot\internal\functions\tabcompletion\Register-DbaTeppScriptblock.ps1").ProviderPath))), $null, $null)
    $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText((Resolve-Path "$ModuleRoot\internal\functions\tabcompletion\Register-DbaTeppInstanceCacheBuilder.ps1").ProviderPath))), $null, $null)

    foreach ($file in (Get-ChildItem (Resolve-Path "$ModuleRoot\internal\dynamicparams\*.ps1").ProviderPath)) {
        $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($file.FullName))), $null, $null)
    }

    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::CalculateTabExpansion()
}
Register-DbaMaintenanceTask -Name "teppInsertTask" -ScriptBlock $scriptBlock -Once
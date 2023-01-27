$scriptBlock = {
    $ModuleRoot = [Dataplat.Dbatools.dbaSystem.SystemHost]::ModuleBase

    $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText((Resolve-Path "$ModuleRoot\private\functions\tabcompletion\Register-DbaTeppScriptblock.ps1").ProviderPath))), $null, $null)
    $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText((Resolve-Path "$ModuleRoot\private\functions\tabcompletion\Register-DbaTeppInstanceCacheBuilder.ps1").ProviderPath))), $null, $null)

    foreach ($file in (Get-ChildItem (Resolve-Path "$ModuleRoot\private\dynamicparams\*.ps1").ProviderPath)) {
        $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($file.FullName))), $null, $null)
    }

    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::CalculateTabExpansion()
}
Register-DbaMaintenanceTask -Name "teppInsertTask" -ScriptBlock $scriptBlock -Once
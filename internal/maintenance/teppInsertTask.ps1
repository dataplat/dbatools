$scriptBlock = {
    $ModuleRoot = [Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleBase

    $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$ModuleRoot\internal\functions\Register-DbaTeppScriptblock.ps1"))), $null, $null)
    $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$ModuleRoot\internal\functions\Register-DbaTeppInstanceCacheBuilder.ps1"))), $null, $null)

    foreach ($file in (Get-ChildItem "$ModuleRoot\internal\dynamicparams\*.ps1")) {
        $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($file.FullName))), $null, $null)
    }

    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::CalculateTabExpansion()
}
Register-DbaMaintenanceTask -Name "teppInsertTask" -ScriptBlock $scriptBlock -Once
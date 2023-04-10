$scriptBlock = {
    $ModuleRoot = [Dataplat.Dbatools.dbaSystem.SystemHost]::ModuleBase

    foreach ($file in (Get-ChildItem -Path "$ModuleRoot\private\functions\tabcompletion" -File)) {
        Import-Command -Path $file.FullName
    }

    foreach ($file in (Get-ChildItem -Path "$ModuleRoot\private\dynamicparams\" -File)) {
        Import-Command -Path $file.FullName
    }

    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::CalculateTabExpansion()
}
Register-DbaMaintenanceTask -Name "teppInsertTask" -ScriptBlock $scriptBlock -Once
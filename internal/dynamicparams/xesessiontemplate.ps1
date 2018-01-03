#region Initialize Cache
if (-not [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["xesessiontemplate"]) {
    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["xesessiontemplate"] = @{ }
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

    (Get-ChildItem "$script:PSModuleRoot\bin\xetemplates\*.xml").BaseName
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name xesessiontemplate
#endregion Tepp Data return
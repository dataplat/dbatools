#region Initialize Cache
if (-not [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["xesessiontemplate"]) {
    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["xesessiontemplate"] = @{ }
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

    $files = (Get-ChildItem "$script:PSModuleRoot/bin/XEtemplates/*.xml").BaseName
    foreach ($file in $files) {
        "'$file'"
    }
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name xesessiontemplate
#endregion Tepp Data return
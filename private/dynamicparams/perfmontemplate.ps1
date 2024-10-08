#region Initialize Cache
if (-not [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["perfmontemplate"]) {
    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["perfmontemplate"] = @{ }
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

    $files = (Get-ChildItem "$script:PSModuleRoot\bin\perfmontemplates\collectorsets\*.xml").BaseName
    foreach ($file in $files) {
        "'$file'"
    }
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name perfmontemplate
#endregion Tepp Data return
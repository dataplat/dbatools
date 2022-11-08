#region Initialize Cache
if (-not [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["delimiter"]) {
    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["delimiter"] = @{ }
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

    @("``t", "|", ";", " ", ",", "       ")
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name Delimiter
#endregion Tepp Data return
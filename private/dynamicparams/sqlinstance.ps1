#region Initialize Cache
if (-not [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"]) {
    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] = @()
}

# Load user-defined instances from config (set via Add-DbaInstanceList)
foreach ($instance in (Get-DbatoolsConfigValue -FullName "TabExpansion.KnownInstances" -Fallback @())) {
    if ($instance -and [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $instance) {
        [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $instance
    }
}

# Load from environment variable (comma-separated list, e.g. set in PowerShell profile)
if ($env:DBATOOLS_KNOWN_INSTANCES) {
    foreach ($instance in ($env:DBATOOLS_KNOWN_INSTANCES -split ",")) {
        $lower = $instance.Trim().ToLowerInvariant()
        if ($lower -and [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $lower) {
            [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $lower
        }
    }
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


    foreach ($name in ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] | Where-DbaObject -Like "$wordToComplete*")) {
        New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
    }
}
Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name "sqlinstance"
#endregion Tepp Data return
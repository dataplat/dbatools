#region Initialize Cache
if (-not [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"]) {
    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] = @()
}

# Load user-defined instances from config (set via Add-DbaInstanceList)
foreach ($instance in (Get-DbatoolsConfigValue -FullName "TabExpansion.KnownInstances" -Fallback @())) {
    Add-DbaTeppInstanceName -Name $instance
}

# Load from environment variable (comma-separated list, e.g. set in PowerShell profile)
if ($env:DBATOOLS_KNOWN_INSTANCES) {
    foreach ($instance in ($env:DBATOOLS_KNOWN_INSTANCES -split ",")) {
        Add-DbaTeppInstanceName -Name $instance
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
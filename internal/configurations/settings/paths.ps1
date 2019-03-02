<#
This is designed for all paths you need configurations for.
#>

# The default path where dbatools stores persistent data
Set-DbatoolsConfig -FullName 'Path.DbatoolsData' -Value (Join-DbaPath $script:AppData "PowerShell" "dbatools") -Initialize -Validation string -Handler {  } -Description "The path where dbatools stores persistent data on a per user basis."

# The default path where dbatools stores temporary data
Set-DbatoolsConfig -FullName 'Path.DbatoolsTemp' -Value ([System.IO.Path]::GetTempPath()).TrimEnd("\") -Initialize -Validation string -Handler { } -Description "The path where dbatools stores temporary data."

# The default path for writing logs
Set-DbatoolsConfig -FullName 'Path.DbatoolsLogPath' -Value (Join-DbaPath $script:AppData "PowerShell" "dbatools") -Initialize -Validation string -Handler { [Sqlcollaborative.Dbatools.Message.LogHost]::LoggingPath = $args[0] } -Description "The path where dbatools writes all its logs and debugging information."

# The default Path for where the tags Json is stored
Set-DbatoolsConfig -FullName 'Path.TagCache' -Value (Resolve-Path "$script:PSModuleRoot\bin\dbatools-index.json") -Initialize -Validation string -Handler { } -Description "The file in which dbatools stores the tag cache. That cache is used in Find-DbaCommand for more comfortable autocomplete"

# The default Path for the server list (Get-DbaServerList, etc)
Set-DbatoolsConfig -FullName 'Path.Servers' -Value (Join-DbaPath $script:AppData "PowerShell" "dbatools" "servers.xml") -Initialize -Validation string -Handler { } -Description "The file in which dbatools stores the current user's server list, as managed by Get/Add/Update-DbaServerList"
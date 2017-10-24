<#
This is designed for all paths you need configurations for.
#>

# The default path where dbatools stores persistent data
Set-DbaConfig -FullName 'Path.DbatoolsData' -Value "$env:AppData\PowerShell\dbatools" -Initialize -Validation string -Handler {  } -Description "The path where dbatools stores persistent data on a per user basis."

# The default path where dbatools stores temporary data
Set-DbaConfig -FullName 'Path.DbatoolsTemp' -Value ([System.IO.Path]::GetTempPath()).TrimEnd("\") -Initialize -Validation string -Handler { } -Description "The path where dbatools stores temporary data."

# The default path for writing logs
Set-DbaConfig -FullName 'Path.DbatoolsLogPath' -Value "$env:AppData\PowerShell\dbatools" -Initialize -Validation string -Handler { [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::LoggingPath = $args[0] } -Description "The path where dbatools writes all its logs and debugging information."

# The default Path for where the tags Json is stored
Set-DbaConfig -FullName 'Path.TagCache' -Value "$ModuleRoot\bin\dbatools-index.json" -Initialize -Validation string -Handler { } -Description "The file in which dbatools stores the tag cache. That cache is used in Find-DbaCommand for more comfortable autocomplete"

# The default Path for the server list (Get-DbaServerList, etc)
Set-DbaConfig -FullName 'Path.Servers' -Value "$env:AppData\PowerShell\dbatools\servers.xml" -Initialize -Validation string -Handler { } -Description "The file in which dbatools stores the current user's server list, as managed by Get/Add/Update-DbaServerList"

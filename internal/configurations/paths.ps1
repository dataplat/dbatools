<#
This is designed for all paths you need configurations for.
#>

# The default path where dbatools stores persistent data
Set-DbaConfig -Name 'Path.DbatoolsData' -Value "$($env:AppData)\PowerShell\dbatools" -Default

# The default path where dbatools stores temporary data
Set-DbaConfig -Name 'Path.DbatoolsTemp' -Value $env:TEMP -Default

# The default path for writing logs
Set-DbaConfig -Name 'Path.DbatoolsLog' -Value "$($env:AppData)\PowerShell\dbatools\dbatools.log" -Default

# The default Path for where the tags Json is stored
Set-DbaConfig -Name 'Path.TagCache' -Value ("$(Resolve-Path $PSScriptRoot\..)\dbatools-index.json") -Default
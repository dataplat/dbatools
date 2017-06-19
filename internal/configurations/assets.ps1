<#
This is designed for all online assets you need configurations for.
#>

# The default path where dbatools stores persistent data
Set-DbaConfig -Name 'assets.sqlbuildreference' -Value 'https://sqlcollaborative.github.io/assets/dbatools-buildref-index.json' -Default -DisableHandler -Description "The url where dbatools fetches the up to date builreference index"

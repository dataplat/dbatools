<#
This is designed for all online assets you need configurations for.
#>

# The default path where dbatools stores persistent data
Set-DbatoolsConfig -FullName 'assets.sqlbuildreference' -Value 'https://sqlcollaborative.github.io/assets/dbatools-buildref-index.json' -Initialize -Validation string -Handler { } -Description "The url where dbatools fetches the up to date buildreference index (e.g. for Get-DbaBuildReference)"
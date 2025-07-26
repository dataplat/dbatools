$ErrorActionPreference = 'Stop'

$repoBase = 'C:\GitHub\dbatools'

Copy-Item -Path "$repoBase\tests\Environment\constants.local.ps1" -Destination "$repoBase\tests\"


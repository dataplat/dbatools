# Runs once per PowerShell worker. Flex Consumption gives app init 30 seconds, so this
# stays to two local module imports -- no Az, no managed dependencies, no network.
#
# No Connect-AzAccount: every Azure call in FleetCore is raw REST against a token from
# the managed identity endpoint, which needs nothing imported.

$ErrorActionPreference = "Stop"

Import-Module -Name "$PSScriptRoot/Modules/GitHubAppAuth/GitHubAppAuth.psm1" -Force
Import-Module -Name "$PSScriptRoot/Modules/FleetCore/FleetCore.psm1" -Force

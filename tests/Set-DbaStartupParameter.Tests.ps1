$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 21
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Set-DbaStartupParameter).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Credential', 'MasterData', 'MasterLog', 'ErrorLog', 'TraceFlags', 'CommandPromptStart', 'MinimalStart', 'MemoryToReserve', 'SingleUser', 'SingleUserDetails', 'NoLoggingToWinEvents', 'StartAsNamedInstance', 'DisableMonitoring', 'IncreasedExtents', 'TraceFlagsOverride', 'StartUpConfig', 'Offline', 'Force', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 23
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Set-DbaAgentJob).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'Schedule', 'ScheduleId', 'NewName', 'Enabled', 'Disabled', 'Description', 'StartStepId', 'Category', 'OwnerLogin', 'EventLogLevel', 'EmailLevel', 'NetsendLevel', 'PageLevel', 'EmailOperator', 'NetsendOperator', 'PageOperator', 'DeleteLevel', 'Force', 'InputObject', 'EnableException'
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
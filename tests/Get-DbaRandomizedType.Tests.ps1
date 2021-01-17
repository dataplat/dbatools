$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'RandomizedType', 'RandomizedSubType', 'Pattern', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command returns types" {

        It "Should have at least 263 rows" {
            $types = Get-DbaRandomizedType

            $types.count | Should BeGreaterOrEqual 205
        }

        It "Should return correct type based on subtype" {
            $result = Get-DbaRandomizedType -RandomizedSubType Zipcode

            $result.Type | Should Be "Address"
        }

        It "Should return values based on pattern" {
            $types = Get-DbaRandomizedType -Pattern Name

            $types.Count | Should BeGreaterOrEqual 26
        }
    }
}
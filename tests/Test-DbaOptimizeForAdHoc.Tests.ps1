$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        $results = Test-DbaOptimizeForAdHoc -SqlInstance $script:instance2
        It "Should return result for the server" {
            $results | Should Not Be Null
        }
        It "Should return 'CurrentOptimizeAdHoc' property as int" {
            $results.CurrentOptimizeAdHoc | Should BeOfType System.Int32
        }
        It "Should return 'RecommendedOptimizeAdHoc' property as int" {
            $results.RecommendedOptimizeAdHoc  | Should BeOfType System.Int32
        }
    }
}
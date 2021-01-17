$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Query', 'Count', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command returns proper info" {
        $results = $instances | Test-DbaNetworkLatency

        It "returns two objects" {
            $results.Count | Should Be 2
        }

        $results = Test-DbaNetworkLatency -SqlInstance $instances

        It "executes 3 times by default" {
            $results.ExecutionCount | Should Be 3, 3
        }

        It "has the correct properties" {
            $result = $results | Select-Object -First 1
            $ExpectedPropsDefault = 'ComputerName,InstanceName,SqlInstance,ExecutionCount,Total,Average,ExecuteOnlyTotal,ExecuteOnlyAverage,NetworkOnlyTotal'.Split(',')
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($ExpectedPropsDefault | Sort-Object)
        }
    }
}
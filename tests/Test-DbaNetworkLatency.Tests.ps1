$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 5
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Test-DbaNetworkLatency).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Query', 'Count', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
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
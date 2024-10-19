param($ModuleName = 'dbatools')

Describe "Test-DbaNetworkLatency" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaNetworkLatency
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Query as a parameter" {
            $CommandUnderTest | Should -HaveParameter Query
        }
        It "Should have Count as a parameter" {
            $CommandUnderTest | Should -HaveParameter Count
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command returns proper info" {
        BeforeAll {
            $results = $instances | Test-DbaNetworkLatency
        }

        It "returns two objects" {
            $results.Count | Should -Be 2
        }

        It "executes 3 times by default" {
            $results = Test-DbaNetworkLatency -SqlInstance $instances
            $results.ExecutionCount | Should -Be @(3, 3)
        }

        It "has the correct properties" {
            $result = $results | Select-Object -First 1
            $ExpectedPropsDefault = 'ComputerName', 'InstanceName', 'SqlInstance', 'ExecutionCount', 'Total', 'Average', 'ExecuteOnlyTotal', 'ExecuteOnlyAverage', 'NetworkOnlyTotal'
            $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object | Should -Be ($ExpectedPropsDefault | Sort-Object)
        }
    }
}

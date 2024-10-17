param($ModuleName = 'dbatools')

Describe "Get-DbaMemoryUsage" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaMemoryUsage
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have MemoryCounterRegex as a parameter" {
            $CommandUnderTest | Should -HaveParameter MemoryCounterRegex -Type String
        }
        It "Should have PlanCounterRegex as a parameter" {
            $CommandUnderTest | Should -HaveParameter PlanCounterRegex -Type String
        }
        It "Should have BufferCounterRegex as a parameter" {
            $CommandUnderTest | Should -HaveParameter BufferCounterRegex -Type String
        }
        It "Should have SSASCounterRegex as a parameter" {
            $CommandUnderTest | Should -HaveParameter SSASCounterRegex -Type String
        }
        It "Should have SSISCounterRegex as a parameter" {
            $CommandUnderTest | Should -HaveParameter SSISCounterRegex -Type String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaMemoryUsage -ComputerName $global:instance1
            $resultsSimple = Get-DbaMemoryUsage -ComputerName $global:instance1
        }

        It "returns results" {
            $results.Count | Should -BeGreaterThan 0
        }

        It "has the correct properties" {
            $result = $results[0]
            $ExpectedProps = 'ComputerName', 'SqlInstance', 'CounterInstance', 'Counter', 'Pages', 'Memory'
            $result.PSObject.Properties.Name | Should -Be $ExpectedProps
        }

        It "returns results for simple query" {
            $resultsSimple.Count | Should -BeGreaterThan 0
        }
    }
}

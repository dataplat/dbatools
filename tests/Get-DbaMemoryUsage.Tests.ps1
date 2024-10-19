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
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "MemoryCounterRegex",
                "PlanCounterRegex",
                "BufferCounterRegex",
                "SSASCounterRegex",
                "SSISCounterRegex",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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

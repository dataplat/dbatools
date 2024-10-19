param($ModuleName = 'dbatools')

Describe "Get-DbaPfDataCollectorCounterSample" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPfDataCollectorCounterSample
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "CollectorSet",
                "Collector",
                "Counter",
                "MaxSamples",
                "SampleInterval",
                "InputObject"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
            $CommandUnderTest | Should -HaveParameter Continuous
            $CommandUnderTest | Should -HaveParameter ListSet
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Verifying command works" {
        BeforeAll {
            $results = Get-DbaPfDataCollectorCounterSample | Select-Object -First 1
        }
        It "returns a result with the right computername" {
            $results.ComputerName | Should -Be $env:COMPUTERNAME
        }
        It "returns a result where name is not null" {
            $results.Name | Should -Not -BeNullOrEmpty
        }
    }
}

param($ModuleName = 'dbatools')

Describe "Get-DbaPfDataCollectorCounterSample" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPfDataCollectorCounterSample
        }

        It "has all the required parameters" {
            $params = @(
                "ComputerName",
                "Credential",
                "CollectorSet",
                "Collector",
                "Counter",
                "Continuous",
                "ListSet",
                "MaxSamples",
                "SampleInterval",
                "InputObject",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
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

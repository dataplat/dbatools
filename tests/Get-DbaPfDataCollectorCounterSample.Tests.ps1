param($ModuleName = 'dbatools')

Describe "Get-DbaPfDataCollectorCounterSample" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPfDataCollectorCounterSample
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have CollectorSet as a parameter" {
            $CommandUnderTest | Should -HaveParameter CollectorSet
        }
        It "Should have Collector as a parameter" {
            $CommandUnderTest | Should -HaveParameter Collector
        }
        It "Should have Counter as a parameter" {
            $CommandUnderTest | Should -HaveParameter Counter
        }
        It "Should have Continuous as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Continuous
        }
        It "Should have ListSet as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ListSet
        }
        It "Should have MaxSamples as a parameter" {
            $CommandUnderTest | Should -HaveParameter MaxSamples
        }
        It "Should have SampleInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter SampleInterval
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a switch parameter" {
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

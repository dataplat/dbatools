param($ModuleName = 'dbatools')

Describe "Get-DbaPfDataCollectorCounterSample" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPfDataCollectorCounterSample
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have CollectorSet as a parameter" {
            $CommandUnderTest | Should -HaveParameter CollectorSet -Type String[]
        }
        It "Should have Collector as a parameter" {
            $CommandUnderTest | Should -HaveParameter Collector -Type String[]
        }
        It "Should have Counter as a parameter" {
            $CommandUnderTest | Should -HaveParameter Counter -Type String[]
        }
        It "Should have Continuous as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Continuous -Type SwitchParameter
        }
        It "Should have ListSet as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ListSet -Type SwitchParameter[]
        }
        It "Should have MaxSamples as a parameter" {
            $CommandUnderTest | Should -HaveParameter MaxSamples -Type Int32
        }
        It "Should have SampleInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter SampleInterval -Type Int32
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[]
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
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

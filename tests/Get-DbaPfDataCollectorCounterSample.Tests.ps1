param($ModuleName = 'dbatools')

Describe "Get-DbaPfDataCollectorCounterSample" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPfDataCollectorCounterSample
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential
        }
        It "Should have CollectorSet as a parameter" {
            $CommandUnderTest | Should -HaveParameter CollectorSet -Type System.String[]
        }
        It "Should have Collector as a parameter" {
            $CommandUnderTest | Should -HaveParameter Collector -Type System.String[]
        }
        It "Should have Counter as a parameter" {
            $CommandUnderTest | Should -HaveParameter Counter -Type System.String[]
        }
        It "Should have Continuous as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Continuous -Type System.Management.Automation.SwitchParameter
        }
        It "Should have ListSet as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ListSet -Type System.Management.Automation.SwitchParameter[]
        }
        It "Should have MaxSamples as a parameter" {
            $CommandUnderTest | Should -HaveParameter MaxSamples -Type System.Int32
        }
        It "Should have SampleInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter SampleInterval -Type System.Int32
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type System.Object[]
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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

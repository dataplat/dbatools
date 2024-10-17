param($ModuleName = 'dbatools')

Describe "Get-DbaFeature" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaFeature
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Verifying command works" {
        BeforeAll {
            $results = Get-DbaFeature | Select-Object -First 1
        }
        It "Returns a result with the right computername" {
            $results.ComputerName | Should -Be $env:COMPUTERNAME
        }
        It "Returns a result with a non-null name" {
            $results.Name | Should -Not -BeNullOrEmpty
        }
    }
}

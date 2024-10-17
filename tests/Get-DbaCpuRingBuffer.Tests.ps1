param($ModuleName = 'dbatools')

Describe "Get-DbaCpuRingBuffer" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaCpuRingBuffer
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have CollectionMinutes as a parameter" {
            $CommandUnderTest | Should -HaveParameter CollectionMinutes -Type Int32
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command returns proper info" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }
        BeforeAll {
            $results = Get-DbaCpuRingBuffer -SqlInstance $script:instance2 -CollectionMinutes 100
        }
        It "Returns results" {
            $results.Count | Should -BeGreaterThan 0
        }
    }
}

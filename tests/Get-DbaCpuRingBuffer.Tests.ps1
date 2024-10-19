param($ModuleName = 'dbatools')

Describe "Get-DbaCpuRingBuffer" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaCpuRingBuffer
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have CollectionMinutes as a parameter" {
            $CommandUnderTest | Should -HaveParameter CollectionMinutes
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command returns proper info" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }
        BeforeAll {
            $results = Get-DbaCpuRingBuffer -SqlInstance $global:instance2 -CollectionMinutes 100
        }
        It "Returns results" {
            $results.Count | Should -BeGreaterThan 0
        }
    }
}

param($ModuleName = 'dbatools')

Describe "Get-DbaReplDistributor" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaReplDistributor
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $results = Get-DbaReplDistributor -SqlInstance $global:instance1
        }

        It "accurately reports that the distributor is not installed" {
            $results.DistributorInstalled | Should -Be $false
        }
    }
}

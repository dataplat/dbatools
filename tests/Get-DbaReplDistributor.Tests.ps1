param($ModuleName = 'dbatools')

Describe "Get-DbaReplDistributor" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaReplDistributor
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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

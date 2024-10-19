param($ModuleName = 'dbatools')

Describe "Get-DbaReplDistributor" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaReplDistributor
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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

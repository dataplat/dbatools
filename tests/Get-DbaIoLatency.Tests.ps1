param($ModuleName = 'dbatools')

Describe "Get-DbaIoLatency" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaIoLatency
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

        It "returns results" {
            $results = Get-DbaIoLatency -SqlInstance $global:instance2
            $results.Count | Should -BeGreaterThan 0
        }
    }
}

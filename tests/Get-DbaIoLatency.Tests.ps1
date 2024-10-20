param($ModuleName = 'dbatools')

Describe "Get-DbaIoLatency" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaIoLatency
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

        It "returns results" {
            $results = Get-DbaIoLatency -SqlInstance $global:instance2
            $results.Count | Should -BeGreaterThan 0
        }
    }
}

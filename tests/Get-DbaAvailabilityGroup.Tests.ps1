param($ModuleName = 'dbatools')

Describe "Get-DbaAvailabilityGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAvailabilityGroup
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "AvailabilityGroup",
            "IsPrimary",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }

        BeforeAll {
            $agname = "dbatoolsci_agroup"
            $null = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
        }

        AfterAll {
            Remove-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -Confirm:$false
        }

        It "returns results with proper data" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $global:instance3
            $results.AvailabilityGroup | Should -Contain $agname
        }

        It "returns a single result" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname
            $results.AvailabilityGroup | Should -Be $agname
        }
    }
} #$global:instance2 for appveyor

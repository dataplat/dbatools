param($ModuleName = 'dbatools')

Describe "Remove-DbaAvailabilityGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAvailabilityGroup
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "AvailabilityGroup",
            "AllAvailabilityGroups",
            "InputObject",
            "EnableException",
            "WhatIf",
            "Confirm"
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
            $agname = "dbatoolsci_removewholegroup"
            $null = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false
        }

        It "removes the newly created ag" {
            $results = Remove-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -Confirm:$false
            $results.Status | Should -Be 'Removed'
            $results.AvailabilityGroup | Should -Be $agname
        }

        It "really removed the ag" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname
            $results | Should -BeNullOrEmpty
        }
    }
} #$global:instance2 for appveyor

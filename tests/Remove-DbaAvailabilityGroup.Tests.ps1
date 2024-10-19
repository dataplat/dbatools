param($ModuleName = 'dbatools')

Describe "Remove-DbaAvailabilityGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAvailabilityGroup
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "AvailabilityGroup",
                "AllAvailabilityGroups",
                "InputObject",
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

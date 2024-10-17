param($ModuleName = 'dbatools')

Describe "Revoke-DbaAgPermission" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Revoke-DbaAgPermission
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type String[]
        }
        It "Should have AvailabilityGroup as a parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup -Type String[]
        }
        It "Should have Type as a parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type String[]
        }
        It "Should have Permission as a parameter" {
            $CommandUnderTest | Should -HaveParameter Permission -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Login[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Integration Tests" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $null = Invoke-DbaQuery -SqlInstance $script:instance3 -InputFile $script:appveyorlabrepo\sql2008-scripts\logins.sql -ErrorAction SilentlyContinue
            $agname = "dbatoolsci_ag_revoke"
            $null = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
        }

        AfterAll {
            $null = Remove-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false
        }

        It "returns results with proper data" {
            $results = Get-DbaLogin -SqlInstance $script:instance3 -Login tester | Revoke-DbaAgPermission -Type EndPoint
            $results.Status | Should -Be 'Success'
        }
    }
} #$script:instance2 for appveyor

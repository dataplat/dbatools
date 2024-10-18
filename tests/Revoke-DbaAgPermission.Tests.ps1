param($ModuleName = 'dbatools')

Describe "Revoke-DbaAgPermission" {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'constants.ps1')
        $CommandUnderTest = Get-Command Revoke-DbaAgPermission
        $null = Invoke-DbaQuery -SqlInstance $global:instance3 -InputFile $global:appveyorlabrepo\sql2008-scripts\logins.sql -ErrorAction SilentlyContinue
        $agname = "dbatoolsci_ag_revoke"
        $null = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
    }

    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -Confirm:$false
    }

    Context "Validate parameters" {
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type System.String[]
        }
        It "Should have AvailabilityGroup as a parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup -Type System.String[]
        }
        It "Should have Type as a parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type System.String[]
        }
        It "Should have Permission as a parameter" {
            $CommandUnderTest | Should -HaveParameter Permission -Type System.String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Login[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Integration Tests" {
        It "returns results with proper data" {
            $results = Get-DbaLogin -SqlInstance $global:instance3 -Login tester | Revoke-DbaAgPermission -Type EndPoint
            $results.Status | Should -Be 'Success'
        }
    }
}

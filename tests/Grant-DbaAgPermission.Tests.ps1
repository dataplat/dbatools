param($ModuleName = 'dbatools')

Describe "Grant-DbaAgPermission" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Grant-DbaAgPermission
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
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Login[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "Grant-DbaAgPermission Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        $null = Invoke-DbaQuery -SqlInstance $global:instance3 -InputFile $env:appveyorlabrepo\sql2008-scripts\logins.sql -ErrorAction SilentlyContinue
        $agname = "dbatoolsci_ag_grant"
        $null = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
    }
    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -Confirm:$false
    }
    Context "grants big perms" {
        It "returns results with proper data" {
            $results = Get-DbaLogin -SqlInstance $global:instance3 -Login tester | Grant-DbaAgPermission -Type EndPoint
            $results.Status | Should -Be 'Success'
        }
    }
} #$global:instance2 for appveyor

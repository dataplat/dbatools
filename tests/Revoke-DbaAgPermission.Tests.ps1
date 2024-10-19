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
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Login",
                "AvailabilityGroup",
                "Type",
                "Permission",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Integration Tests" {
        It "returns results with proper data" {
            $results = Get-DbaLogin -SqlInstance $global:instance3 -Login tester | Revoke-DbaAgPermission -Type EndPoint
            $results.Status | Should -Be 'Success'
        }
    }
}

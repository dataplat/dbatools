param($ModuleName = 'dbatools')
Describe "Remove-DbaAgListener" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAgListener
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Listener",
                "AvailabilityGroup",
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
            $agname = "dbatoolsci_ag_removelistener"
            $ag = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
            $aglistener = $ag | Add-DbaAgListener -IPAddress 127.0.20.1 -Port 14330 -Confirm:$false
        }

        AfterAll {
            $null = Remove-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -Confirm:$false
        }

        It "removes a listener" {
            $results = Remove-DbaAgListener -SqlInstance $global:instance3 -Listener $aglistener.Name -Confirm:$false
            $results.Status | Should -Be 'Removed'
        }
    }
} #$global:instance2 for appveyor

param($ModuleName = 'dbatools')
Describe "Remove-DbaAgListener" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAgListener
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Listener as a parameter" {
            $CommandUnderTest | Should -HaveParameter Listener
        }
        It "Should have AvailabilityGroup as a parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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

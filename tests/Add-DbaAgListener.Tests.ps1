param($ModuleName = 'dbatools')

Describe "Add-DbaAgListener" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Add-DbaAgListener
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have AvailabilityGroup as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup
        }
        It "Should have Name as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have IPAddress as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter IPAddress
        }
        It "Should have SubnetIP as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SubnetIP
        }
        It "Should have SubnetMask as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SubnetMask
        }
        It "Should have Port as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Port
        }
        It "Should have Dhcp as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Dhcp
        }
        It "Should have Passthru as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Passthru
        }
        It "Should have InputObject as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeAll {
            $agname = "dbatoolsci_ag_newlistener"
            $listenerName = 'dbatoolsci_listener'
            $ag = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
        }
        AfterEach {
            $null = Remove-DbaAgListener -SqlInstance $global:instance3 -Listener $listenerName -AvailabilityGroup $agname -Confirm:$false
        }
        AfterAll {
            $null = Remove-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -Confirm:$false
        }
        It "creates a listener and returns results with proper data" {
            $results = $ag | Add-DbaAgListener -Name $listenerName -IPAddress 127.0.20.1 -Port 14330 -Confirm:$false
            $results.PortNumber | Should -Be 14330
        }
    }
} #$global:instance2 for appveyor

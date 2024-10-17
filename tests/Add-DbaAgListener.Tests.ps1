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
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have AvailabilityGroup as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup -Type String[] -Not -Mandatory
        }
        It "Should have Name as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Name -Type String -Not -Mandatory
        }
        It "Should have IPAddress as a non-mandatory parameter of type IPAddress[]" {
            $CommandUnderTest | Should -HaveParameter IPAddress -Type IPAddress[] -Not -Mandatory
        }
        It "Should have SubnetIP as a non-mandatory parameter of type IPAddress[]" {
            $CommandUnderTest | Should -HaveParameter SubnetIP -Type IPAddress[] -Not -Mandatory
        }
        It "Should have SubnetMask as a non-mandatory parameter of type IPAddress[]" {
            $CommandUnderTest | Should -HaveParameter SubnetMask -Type IPAddress[] -Not -Mandatory
        }
        It "Should have Port as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter Port -Type Int32 -Not -Mandatory
        }
        It "Should have Dhcp as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Dhcp -Type Switch -Not -Mandatory
        }
        It "Should have Passthru as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Passthru -Type Switch -Not -Mandatory
        }
        It "Should have InputObject as a non-mandatory parameter of type AvailabilityGroup[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type AvailabilityGroup[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
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

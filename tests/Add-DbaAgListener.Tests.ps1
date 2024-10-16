$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandUnderTest = Get-Command $CommandName
    }
    Context "Validate parameters" {
        It "Should have the correct parameters" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup -Type String[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Name -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter IPAddress -Type IPAddress[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter SubnetIP -Type IPAddress[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter SubnetMask -Type IPAddress[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Port -Type Int32 -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Dhcp -Type SwitchParameter -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Passthru -Type SwitchParameter -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter InputObject -Type AvailabilityGroup[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_ag_newlistener"
        $listenerName = 'dbatoolsci_listener'
        $ag = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
    }
    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false
    }
    Context "creates a listener" {
        BeforeEach {
            $null = Remove-DbaAgListener -SqlInstance $script:instance3 -Listener $listenerName -AvailabilityGroup $agname -Confirm:$false
        }
        It "returns results with proper data" {
            $results = $ag | Add-DbaAgListener -Name $listenerName -IPAddress 127.0.20.1 -Port 14330 -Confirm:$false
            $results.PortNumber | Should -Be 14330
        }
    }
} #$script:instance2 for appveyor

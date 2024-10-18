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
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have AvailabilityGroup as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup -Type System.String[] -Mandatory:$false
        }
        It "Should have Name as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Name -Type System.String -Mandatory:$false
        }
        It "Should have IPAddress as a non-mandatory parameter of type System.Net.IPAddress[]" {
            $CommandUnderTest | Should -HaveParameter IPAddress -Type System.Net.IPAddress[] -Mandatory:$false
        }
        It "Should have SubnetIP as a non-mandatory parameter of type System.Net.IPAddress[]" {
            $CommandUnderTest | Should -HaveParameter SubnetIP -Type System.Net.IPAddress[] -Mandatory:$false
        }
        It "Should have SubnetMask as a non-mandatory parameter of type System.Net.IPAddress[]" {
            $CommandUnderTest | Should -HaveParameter SubnetMask -Type System.Net.IPAddress[] -Mandatory:$false
        }
        It "Should have Port as a non-mandatory parameter of type System.Int32" {
            $CommandUnderTest | Should -HaveParameter Port -Type System.Int32 -Mandatory:$false
        }
        It "Should have Dhcp as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Dhcp -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have Passthru as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Passthru -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter of type Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.AvailabilityGroup[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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

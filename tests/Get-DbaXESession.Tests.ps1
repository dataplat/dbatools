param($ModuleName = 'dbatools')

Describe "Get-DbaXESession" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaXESession
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Session as a non-mandatory parameter of type System.Object[]" {
            $CommandUnderTest | Should -HaveParameter Session -Type System.Object[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Verifying command output" {
        It "returns some results" {
            $results = Get-DbaXESession -SqlInstance $global:instance2
            $results.Count | Should -BeGreaterThan 1
        }

        It "returns only the system_health session" {
            $results = Get-DbaXESession -SqlInstance $global:instance2 -Session system_health
            $results.Name | Should -Be 'system_health'
        }
    }
}

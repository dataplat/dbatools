param($ModuleName = 'dbatools')

Describe "Get-DbaDbccUserOption" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbccUserOption
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Option as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Option -Type System.String[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeAll {
            $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Option', 'Value'
            $result = Get-DbaDbccUserOption -SqlInstance $global:instance2
        }

        It "Should return property: <_>" -ForEach $props {
            $result[0].PSObject.Properties[$_] | Should -Not -BeNullOrEmpty
        }

        It "Should return results for DBCC USEROPTIONS" {
            $result.Count | Should -BeGreaterThan 0
        }

        It "Should accept an Option value" {
            $optionResult = Get-DbaDbccUserOption -SqlInstance $global:instance2 -Option ansi_nulls
            $optionResult | Should -Not -BeNullOrEmpty
            $optionResult.Option | Should -Be 'ansi_nulls'
        }
    }
}

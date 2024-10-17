param($ModuleName = 'dbatools')

Describe "Get-DbaDbccUserOption" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbccUserOption
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Option as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Option -Type String[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
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

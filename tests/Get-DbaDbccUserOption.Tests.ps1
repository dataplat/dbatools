param($ModuleName = 'dbatools')

Describe "Get-DbaDbccUserOption" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbccUserOption
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Option",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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

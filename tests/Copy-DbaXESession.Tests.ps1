param($ModuleName = 'dbatools')

Describe "Copy-DbaXESession" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaXESession
        }
        It "Should have Source parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter
        }
        It "Should have Destination parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SourceSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have DestinationSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have XeSession parameter" {
            $CommandUnderTest | Should -HaveParameter XeSession -Type System.Object[]
        }
        It "Should have ExcludeXeSession parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeXeSession -Type System.Object[]
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeAll {
            # Add any necessary setup code here
        }

        It "Example test" {
            # Add actual tests here
            $true | Should -Be $true
        }
    }
}

<#
    Integration tests should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>

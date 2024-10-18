param($ModuleName = 'dbatools')

Describe "Reset-DbatoolsConfig" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Reset-DbatoolsConfig
        }
        It "Should have ConfigurationItem as a non-mandatory parameter of type Dataplat.Dbatools.Configuration.Config[]" {
            $CommandUnderTest | Should -HaveParameter ConfigurationItem -Type Dataplat.Dbatools.Configuration.Config[] -Mandatory:$false
        }
        It "Should have FullName as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter FullName -Type System.String[] -Mandatory:$false
        }
        It "Should have Module as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Module -Type System.String -Mandatory:$false
        }
        It "Should have Name as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Name -Type System.String -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have WhatIf as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have Confirm as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }
}

# Integration tests can be added here
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance

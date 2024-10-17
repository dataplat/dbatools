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
        It "Should have ConfigurationItem as a non-mandatory parameter of type Config[]" {
            $CommandUnderTest | Should -HaveParameter ConfigurationItem -Type Config[] -Not -Mandatory
        }
        It "Should have FullName as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter FullName -Type String[] -Not -Mandatory
        }
        It "Should have Module as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Module -Type String -Not -Mandatory
        }
        It "Should have Name as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Name -Type String -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
        It "Should have Verbose as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch -Not -Mandatory
        }
        It "Should have Debug as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch -Not -Mandatory
        }
        It "Should have ErrorAction as a non-mandatory parameter of type ActionPreference" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have WarningAction as a non-mandatory parameter of type ActionPreference" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have InformationAction as a non-mandatory parameter of type ActionPreference" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have ProgressAction as a non-mandatory parameter of type ActionPreference" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have ErrorVariable as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String -Not -Mandatory
        }
        It "Should have WarningVariable as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String -Not -Mandatory
        }
        It "Should have InformationVariable as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String -Not -Mandatory
        }
        It "Should have OutVariable as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String -Not -Mandatory
        }
        It "Should have OutBuffer as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32 -Not -Mandatory
        }
        It "Should have PipelineVariable as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String -Not -Mandatory
        }
        It "Should have WhatIf as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf -Type Switch -Not -Mandatory
        }
        It "Should have Confirm as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm -Type Switch -Not -Mandatory
        }
    }
}

# Integration tests can be added here
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance

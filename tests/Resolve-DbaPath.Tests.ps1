param($ModuleName = 'dbatools')

Describe "Resolve-DbaPath Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Resolve-DbaPath
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String[] -Not -Mandatory
        }
        It "Should have Provider as a parameter" {
            $CommandUnderTest | Should -HaveParameter Provider -Type String -Not -Mandatory
        }
        It "Should have SingleItem as a parameter" {
            $CommandUnderTest | Should -HaveParameter SingleItem -Type Switch -Not -Mandatory
        }
        It "Should have NewChild as a parameter" {
            $CommandUnderTest | Should -HaveParameter NewChild -Type Switch -Not -Mandatory
        }
        It "Should have Verbose as a parameter" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch -Not -Mandatory
        }
        It "Should have Debug as a parameter" {
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch -Not -Mandatory
        }
        It "Should have ErrorAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have WarningAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have InformationAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have ProgressAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have ErrorVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String -Not -Mandatory
        }
        It "Should have WarningVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String -Not -Mandatory
        }
        It "Should have InformationVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String -Not -Mandatory
        }
        It "Should have OutVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String -Not -Mandatory
        }
        It "Should have OutBuffer as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32 -Not -Mandatory
        }
        It "Should have PipelineVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String -Not -Mandatory
        }
    }
}

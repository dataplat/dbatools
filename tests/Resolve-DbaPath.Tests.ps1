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
            $CommandUnderTest | Should -HaveParameter Path -Type System.String[] -Mandatory:$false
        }
        It "Should have Provider as a parameter" {
            $CommandUnderTest | Should -HaveParameter Provider -Type System.String -Mandatory:$false
        }
        It "Should have SingleItem as a parameter" {
            $CommandUnderTest | Should -HaveParameter SingleItem -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have NewChild as a parameter" {
            $CommandUnderTest | Should -HaveParameter NewChild -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }
}

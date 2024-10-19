param($ModuleName = 'dbatools')

Describe "Set-DbatoolsPath" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbatoolsPath
        }
        It "Should have Name as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have Path as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have Register as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Register
        }
        It "Should have Scope as a non-mandatory ConfigScope parameter" {
            $CommandUnderTest | Should -HaveParameter Scope
        }
    }
}

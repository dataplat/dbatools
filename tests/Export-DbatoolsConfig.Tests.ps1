param($ModuleName = 'dbatools')

Describe "Export-DbatoolsConfig" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbatoolsConfig
        }
        It "Should have FullName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter FullName
        }
        It "Should have Module as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Module
        }
        It "Should have Name as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have Config as a non-mandatory Config[] parameter" {
            $CommandUnderTest | Should -HaveParameter Config
        }
        It "Should have ModuleName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter ModuleName
        }
        It "Should have ModuleVersion as a non-mandatory Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter ModuleVersion
        }
        It "Should have Scope as a non-mandatory ConfigScope parameter" {
            $CommandUnderTest | Should -HaveParameter Scope
        }
        It "Should have OutPath as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter OutPath
        }
        It "Should have SkipUnchanged as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter SkipUnchanged
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

# Integration tests can be added here
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance

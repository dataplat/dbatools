param($ModuleName = 'dbatools')

Describe "Import-DbatoolsConfig" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Import-DbatoolsConfig
        }
        It "Should have Path as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have ModuleName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ModuleName
        }
        It "Should have ModuleVersion as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ModuleVersion
        }
        It "Should have Scope as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Scope
        }
        It "Should have IncludeFilter as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeFilter
        }
        It "Should have ExcludeFilter as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeFilter
        }
        It "Should have Peek as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Peek
        }
        It "Should have EnableException as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

<#
    Integration tests are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance
#>

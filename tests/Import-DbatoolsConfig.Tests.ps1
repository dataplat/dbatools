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
        It "Should have Path as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String[] -Mandatory:$false
        }
        It "Should have ModuleName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter ModuleName -Type String -Mandatory:$false
        }
        It "Should have ModuleVersion as a non-mandatory Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter ModuleVersion -Type Int32 -Mandatory:$false
        }
        It "Should have Scope as a non-mandatory ConfigScope parameter" {
            $CommandUnderTest | Should -HaveParameter Scope -Type ConfigScope -Mandatory:$false
        }
        It "Should have IncludeFilter as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeFilter -Type String[] -Mandatory:$false
        }
        It "Should have ExcludeFilter as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeFilter -Type String[] -Mandatory:$false
        }
        It "Should have Peek as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Peek -Type Switch -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }
}

<#
    Integration tests are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance
#>

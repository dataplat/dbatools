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
        It "Should have Path as a non-mandatory System.String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.String[] -Mandatory:$false
        }
        It "Should have ModuleName as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter ModuleName -Type System.String -Mandatory:$false
        }
        It "Should have ModuleVersion as a non-mandatory System.Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter ModuleVersion -Type System.Int32 -Mandatory:$false
        }
        It "Should have Scope as a non-mandatory Dataplat.Dbatools.Configuration.ConfigScope parameter" {
            $CommandUnderTest | Should -HaveParameter Scope -Type Dataplat.Dbatools.Configuration.ConfigScope -Mandatory:$false
        }
        It "Should have IncludeFilter as a non-mandatory System.String[] parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeFilter -Type System.String[] -Mandatory:$false
        }
        It "Should have ExcludeFilter as a non-mandatory System.String[] parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeFilter -Type System.String[] -Mandatory:$false
        }
        It "Should have Peek as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Peek -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }
}

<#
    Integration tests are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance
#>

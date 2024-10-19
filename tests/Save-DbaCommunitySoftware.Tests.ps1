param($ModuleName = 'dbatools')

Describe "Save-DbaCommunitySoftware" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Save-DbaCommunitySoftware
        }
        It "Should have Software as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Software
        }
        It "Should have Branch as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Branch
        }
        It "Should have LocalFile as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter LocalFile
        }
        It "Should have Url as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Url
        }
        It "Should have LocalDirectory as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter LocalDirectory
        }
        It "Should have EnableException as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    # Add more contexts and tests as needed
}

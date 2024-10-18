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
        It "Should have Software as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Software -Type System.String -Mandatory:$false
        }
        It "Should have Branch as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Branch -Type System.String -Mandatory:$false
        }
        It "Should have LocalFile as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter LocalFile -Type System.String -Mandatory:$false
        }
        It "Should have Url as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Url -Type System.String -Mandatory:$false
        }
        It "Should have LocalDirectory as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter LocalDirectory -Type System.String -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    # Add more contexts and tests as needed
}

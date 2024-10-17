param($ModuleName = 'dbatools')

Describe "Get-DbaXESessionTemplate" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaXESessionTemplate
        }
        It "Should have Path as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String[] -Mandatory:$false
        }
        It "Should have Pattern as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Pattern -Type String -Mandatory:$false
        }
        It "Should have Template as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Template -Type String[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Get Template Index" {
        BeforeAll {
            $results = Get-DbaXESessionTemplate
        }
        It "returns good results with no missing information" {
            $results | Where-Object Name -eq $null | Should -BeNullOrEmpty
            $results | Where-Object TemplateName -eq $null | Should -BeNullOrEmpty
            $results | Where-Object Description -eq $null | Should -BeNullOrEmpty
            $results | Where-Object Category -eq $null | Should -BeNullOrEmpty
        }
    }
}

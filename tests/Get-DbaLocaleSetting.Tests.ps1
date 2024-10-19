param($ModuleName = 'dbatools')

Describe "Get-DbaLocaleSetting" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaLocaleSetting
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Gets LocaleSettings" {
        BeforeAll {
            $results = Get-DbaLocaleSetting -ComputerName $env:ComputerName
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}

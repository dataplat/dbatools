param($ModuleName = 'dbatools')

Describe "Get-DbaNetworkActivity" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaNetworkActivity
        }
        It "Should have ComputerName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Gets Network Activity" {
        BeforeAll {
            $results = Get-DbaNetworkActivity -ComputerName $env:ComputerName
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}

param($ModuleName = 'dbatools')

Describe "Get-DbaConnectedInstance" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaConnectedInstance
        }

        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $global:instance1
        }

        It "returns some results" {
            $results = Get-DbaConnectedInstance
            $results | Should -Not -BeNullOrEmpty
        }
    }
}

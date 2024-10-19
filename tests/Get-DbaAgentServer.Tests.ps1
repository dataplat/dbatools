param($ModuleName = 'dbatools')

Describe "Get-DbaAgentServer" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgentServer
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command gets server agent" {
        BeforeAll {
            $results = Get-DbaAgentServer -SqlInstance $global:instance2
        }
        It "Should get 1 agent server" {
            $results.count | Should -Be 1
        }
    }
}

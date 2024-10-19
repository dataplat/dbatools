param($ModuleName = 'dbatools')

Describe "Get-DbaEndpoint" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaEndpoint
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Endpoint",
                "Type",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
        }

        It "gets some endpoints" {
            $results = Get-DbaEndpoint -SqlInstance $global:instance2
            $results.Count | Should -BeGreaterThan 1
            $results.Name | Should -Contain 'TSQL Default TCP'
        }

        It "gets one endpoint" {
            $results = Get-DbaEndpoint -SqlInstance $global:instance2 -Endpoint 'TSQL Default TCP'
            $results.Name | Should -Be 'TSQL Default TCP'
            $results.Count | Should -Be 1
        }
    }
}

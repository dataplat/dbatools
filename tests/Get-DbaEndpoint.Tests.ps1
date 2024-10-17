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
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Endpoint as a parameter" {
            $CommandUnderTest | Should -HaveParameter Endpoint -Type String[]
        }
        It "Should have Type as a parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type String[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
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

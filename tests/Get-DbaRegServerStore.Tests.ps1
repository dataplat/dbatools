param($ModuleName = 'dbatools')

Describe "Get-DbaRegServerStore" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRegServerStore
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Components are properly retrieved" {
        It "Should return the right values" {
            $results = Get-DbaRegServerStore -SqlInstance $global:instance2
            $results.InstanceName | Should -Not -BeNullOrEmpty
            $results.DisplayName | Should -Be "Central Management Servers"
        }
    }
}

param($ModuleName = 'dbatools')

Describe "Get-DbaFilestream" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaFilestream
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Credential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Getting FileStream Level" {
        BeforeAll {
            $results = Get-DbaFilestream -SqlInstance $global:instance2
        }
        It "Should have changed the FileStream Level" {
            $results.InstanceAccess | Should -BeIn 'Disabled', 'T-SQL access enabled', 'Full access enabled'
        }
    }
}

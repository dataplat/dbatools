param($ModuleName = 'dbatools')

Describe "New-DbaClientAlias" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaClientAlias
        }
        $params = @(
            "ComputerName",
            "Credential",
            "ServerName",
            "Alias",
            "Protocol",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Functionality" -Tag "IntegrationTests" {
        It "adds the alias" {
            $results = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias-new
            $results.AliasName | Should -Be @('dbatoolscialias-new', 'dbatoolscialias-new')
            $results | Remove-DbaClientAlias
        }
    }
}

param($ModuleName = 'dbatools')

Describe "Test-DbaCmConnection" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaCmConnection
        }
        $params = @(
            "ComputerName",
            "Credential",
            "Type",
            "Force",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        It "returns some valid info" {
            $results = Test-DbaCmConnection -Type Wmi
            $results.ComputerName | Should -Be $env:COMPUTERNAME
            $results.Available | Should -BeOfType [bool]
        }
    }
}

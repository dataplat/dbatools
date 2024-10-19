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
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "Type",
                "Force",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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

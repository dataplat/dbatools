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
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have Type as a parameter" {
            $CommandUnderTest | Should -HaveParameter Type
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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

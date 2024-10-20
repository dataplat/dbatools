param($ModuleName = 'dbatools')

Describe "Get-DbaClientProtocol" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaClientProtocol
        }
        $params = @(
            "ComputerName",
            "Credential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Get some client protocols" {
        BeforeAll {
            $results = Get-DbaClientProtocol
        }
        It "Should return some protocols" {
            $results.Count | Should -BeGreaterThan 1
        }
        It "Should include TCP/IP protocol" {
            $results | Where-Object { $_.ProtocolDisplayName -eq 'TCP/IP' } | Should -Not -BeNullOrEmpty
        }
    }
}

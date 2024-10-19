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
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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

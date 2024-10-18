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
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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

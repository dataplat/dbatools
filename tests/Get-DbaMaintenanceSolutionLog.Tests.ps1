param($ModuleName = 'dbatools')

Describe "Get-DbaMaintenanceSolutionLog" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaMaintenanceSolutionLog
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have LogType as a parameter" {
            $CommandUnderTest | Should -HaveParameter LogType -Type String[]
        }
        It "Should have Since as a parameter" {
            $CommandUnderTest | Should -HaveParameter Since -Type DateTime
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    # Add more contexts and tests as needed for integration testing
    # For example:
    # Context "Command Execution" {
    #     BeforeAll {
    #         # Setup code
    #     }
    #     It "Should return expected results" {
    #         # Test code
    #     }
    #     AfterAll {
    #         # Cleanup code
    #     }
    # }
}

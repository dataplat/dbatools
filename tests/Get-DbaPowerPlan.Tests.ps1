param($ModuleName = 'dbatools')

Describe "Get-DbaPowerPlan" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPowerPlan
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have List as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter List -Type switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch
        }
    }

    Context "Command actually works" {
        BeforeDiscovery {
            $script:instance2 = $script:instance2 # Ensure this variable is available in the discovery phase
        }
        It "Should return result for the server" {
            $results = Get-DbaPowerPlan -ComputerName $script:instance2
            $results | Should -Not -BeNullOrEmpty
        }
    }
}

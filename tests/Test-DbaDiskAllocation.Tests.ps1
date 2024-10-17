param($ModuleName = 'dbatools')

Describe "Test-DbaDiskAllocation" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaDiskAllocation
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type Object[] -Not -Mandatory
        }
        It "Should have NoSqlCheck as a parameter" {
            $CommandUnderTest | Should -HaveParameter NoSqlCheck -Type Switch -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Command actually works" {
        BeforeDiscovery {
            $env:instance2 = $env:instance2 # Ensure this variable is in scope for discovery
        }
        It "Should return a result" {
            $results = Test-DbaDiskAllocation -ComputerName $env:instance2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return a result not using sql" {
            $results = Test-DbaDiskAllocation -NoSqlCheck -ComputerName $env:instance2
            $results | Should -Not -BeNullOrEmpty
        }
    }
}

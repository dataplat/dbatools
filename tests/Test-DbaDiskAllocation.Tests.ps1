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
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have NoSqlCheck as a parameter" {
            $CommandUnderTest | Should -HaveParameter NoSqlCheck
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command actually works" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }
        It "Should return a result" {
            $results = Test-DbaDiskAllocation -ComputerName $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return a result not using sql" {
            $results = Test-DbaDiskAllocation -NoSqlCheck -ComputerName $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }
    }
}

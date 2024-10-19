param($ModuleName = 'dbatools')

Describe "Test-DbaDiskAlignment" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaDiskAlignment
        }
        It "Should have ComputerName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have NoSqlCheck as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoSqlCheck
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $env:dbatoolsci_computer = $env:COMPUTERNAME  # This is a placeholder. Replace with actual value if different.
        }
        It "Should return a result" {
            $results = Test-DbaDiskAlignment -ComputerName $env:dbatoolsci_computer
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return a result not using sql" {
            $results = Test-DbaDiskAlignment -NoSqlCheck -ComputerName $env:dbatoolsci_computer
            $results | Should -Not -BeNullOrEmpty
        }
    }
}

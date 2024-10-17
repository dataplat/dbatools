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
        It "Should have ComputerName as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have NoSqlCheck as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoSqlCheck -Type switch -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Not -Mandatory
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $script:dbatoolsci_computer = $env:COMPUTERNAME  # This is a placeholder. Replace with actual value if different.
        }
        It "Should return a result" {
            $results = Test-DbaDiskAlignment -ComputerName $script:dbatoolsci_computer
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return a result not using sql" {
            $results = Test-DbaDiskAlignment -NoSqlCheck -ComputerName $script:dbatoolsci_computer
            $results | Should -Not -BeNullOrEmpty
        }
    }
}

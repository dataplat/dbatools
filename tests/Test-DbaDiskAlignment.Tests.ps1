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
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "SqlCredential",
                "NoSqlCheck",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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

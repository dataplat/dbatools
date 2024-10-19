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
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "NoSqlCheck",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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

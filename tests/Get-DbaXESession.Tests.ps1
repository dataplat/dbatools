param($ModuleName = 'dbatools')

Describe "Get-DbaXESession" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaXESession
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Session",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Verifying command output" {
        It "returns some results" {
            $results = Get-DbaXESession -SqlInstance $global:instance2
            $results.Count | Should -BeGreaterThan 1
        }

        It "returns only the system_health session" {
            $results = Get-DbaXESession -SqlInstance $global:instance2 -Session system_health
            $results.Name | Should -Be 'system_health'
        }
    }
}

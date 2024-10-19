param($ModuleName = 'dbatools')

Describe "Get-DbaLatchStatistic" {
    BeforeAll {
        $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaLatchStatistic
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Threshold",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command returns proper info" {
        BeforeAll {
            $results = Get-DbaLatchStatistic -SqlInstance $global:instance2 -Threshold 100
        }

        It "returns results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "returns a hyperlink for each result" {
            foreach ($result in $results) {
                $result.URL | Should -Match 'sqlskills.com'
            }
        }
    }
}

$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = New-DbaAgentJobCategory -SqlInstance $script:instance2 -Category 'dbatoolsci test category'
    }
    AfterAll {
        $null = Remove-DbaAgentJobCategory -SqlInstance $script:instance2 -Category 'dbatoolsci test category'
    }
    
    Context "Command copies jobs properly" {
        It "returns one success" {
            $results = Copy-DbaAgentCategory -Source $script:instance2 -Destination $script:instance3 -JobCategory 'dbatoolsci test category'
            $results.Name -eq "dbatoolsci test category"
            $results.Status -eq "Successful"
        }

        It "does not overwrite" {
            $results = Copy-DbaAgentCategory -Source $script:instance2 -Destination $script:instance3 -JobCategory 'dbatoolsci test category'
            $results.Name -eq "dbatoolsci test category"
            $results.Status -eq "Skipped"
        }
    }
}
param($ModuleName = 'dbatools')

Describe "New-DbaXESmartQueryExec" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaXESmartQueryExec
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Query",
                "EnableException",
                "Event",
                "Filter"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Creates a smart object" {
        BeforeAll {
            $results = New-DbaXESmartQueryExec -SqlInstance $global:instance2 -Database dbadb -Query "update table set whatever = 1"
        }
        It "returns the object with all of the correct properties" {
            $results.TSQL | Should -Be 'update table set whatever = 1'
            $results.ServerName | Should -Be $global:instance2
            $results.DatabaseName | Should -Be 'dbadb'
            $results.Password | Should -BeNullOrEmpty
        }
    }
}

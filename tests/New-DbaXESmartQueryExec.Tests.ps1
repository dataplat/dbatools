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
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have Query as a parameter" {
            $CommandUnderTest | Should -HaveParameter Query
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Should have Event as a parameter" {
            $CommandUnderTest | Should -HaveParameter Event
        }
        It "Should have Filter as a parameter" {
            $CommandUnderTest | Should -HaveParameter Filter
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

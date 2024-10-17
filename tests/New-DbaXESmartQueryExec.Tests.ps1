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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String
        }
        It "Should have Query as a parameter" {
            $CommandUnderTest | Should -HaveParameter Query -Type String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
        It "Should have Event as a parameter" {
            $CommandUnderTest | Should -HaveParameter Event -Type String[]
        }
        It "Should have Filter as a parameter" {
            $CommandUnderTest | Should -HaveParameter Filter -Type String
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

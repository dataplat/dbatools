param($ModuleName = 'dbatools')

Describe "New-DbaXESmartTableWriter" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaXESmartTableWriter
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have Table as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Table
        }
        It "Should have AutoCreateTargetTable as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter AutoCreateTargetTable
        }
        It "Should have UploadIntervalSeconds as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter UploadIntervalSeconds
        }
        It "Should have Event as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Event
        }
        It "Should have OutputColumn as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter OutputColumn
        }
        It "Should have Filter as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Filter
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Creates a smart object" {
        BeforeAll {
            $results = New-DbaXESmartReplay -SqlInstance $global:instance2 -Database planning
        }
        It "returns the object with all of the correct properties" {
            $results.ServerName | Should -Be $global:instance2
            $results.DatabaseName | Should -Be 'planning'
            $results.Password | Should -BeNullOrEmpty
            $results.DelaySeconds | Should -Be 0
        }
    }
}

param($ModuleName = 'dbatools')

Describe "New-DbaXESmartReplay" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaXESmartReplay
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String -Not -Mandatory
        }
        It "Should have Event parameter" {
            $CommandUnderTest | Should -HaveParameter Event -Type String[] -Not -Mandatory
        }
        It "Should have Filter parameter" {
            $CommandUnderTest | Should -HaveParameter Filter -Type String -Not -Mandatory
        }
        It "Should have DelaySeconds parameter" {
            $CommandUnderTest | Should -HaveParameter DelaySeconds -Type Int32 -Not -Mandatory
        }
        It "Should have StopOnError parameter" {
            $CommandUnderTest | Should -HaveParameter StopOnError -Type Switch -Not -Mandatory
        }
        It "Should have ReplayIntervalSeconds parameter" {
            $CommandUnderTest | Should -HaveParameter ReplayIntervalSeconds -Type Int32 -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }
}

Describe "New-DbaXESmartReplay Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $env:instance2 = [Environment]::GetEnvironmentVariable("instance2")
    }

    Context "Creates a smart object" {
        It "returns the object with all of the correct properties" {
            $columns = "cpu_time", "duration", "physical_reads", "logical_reads", "writes", "row_count", "batch_text"
            $results = New-DbaXESmartTableWriter -SqlInstance $env:instance2 -Database dbadb -Table deadlocktracker -OutputColumn $columns -Filter "duration > 10000"
            $results.ServerName | Should -Be $env:instance2
            $results.DatabaseName | Should -Be 'dbadb'
            $results.Password | Should -BeNullOrEmpty
            $results.TableName | Should -Be 'deadlocktracker'
            $results.IsSingleEvent | Should -BeTrue
            $results.FailOnSingleEventViolation | Should -BeFalse
        }
    }
}

param($ModuleName = 'dbatools')

Describe "New-DbaXESmartReplay" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaXESmartReplay
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String -Mandatory:$false
        }
        It "Should have Event parameter" {
            $CommandUnderTest | Should -HaveParameter Event -Type System.String[] -Mandatory:$false
        }
        It "Should have Filter parameter" {
            $CommandUnderTest | Should -HaveParameter Filter -Type System.String -Mandatory:$false
        }
        It "Should have DelaySeconds parameter" {
            $CommandUnderTest | Should -HaveParameter DelaySeconds -Type System.Int32 -Mandatory:$false
        }
        It "Should have StopOnError parameter" {
            $CommandUnderTest | Should -HaveParameter StopOnError -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have ReplayIntervalSeconds parameter" {
            $CommandUnderTest | Should -HaveParameter ReplayIntervalSeconds -Type System.Int32 -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }
}

Describe "New-DbaXESmartReplay Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Creates a smart object" {
        It "returns the object with all of the correct properties" {
            $columns = "cpu_time", "duration", "physical_reads", "logical_reads", "writes", "row_count", "batch_text"
            $results = New-DbaXESmartTableWriter -SqlInstance $global:instance2 -Database dbadb -Table deadlocktracker -OutputColumn $columns -Filter "duration > 10000"
            $results.ServerName | Should -Be $global:instance2
            $results.DatabaseName | Should -Be 'dbadb'
            $results.Password | Should -BeNullOrEmpty
            $results.TableName | Should -Be 'deadlocktracker'
            $results.IsSingleEvent | Should -BeTrue
            $results.FailOnSingleEventViolation | Should -BeFalse
        }
    }
}

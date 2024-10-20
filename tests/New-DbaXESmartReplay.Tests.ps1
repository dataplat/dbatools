param($ModuleName = 'dbatools')

Describe "New-DbaXESmartReplay" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaXESmartReplay
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "Event",
            "Filter",
            "DelaySeconds",
            "StopOnError",
            "ReplayIntervalSeconds",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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

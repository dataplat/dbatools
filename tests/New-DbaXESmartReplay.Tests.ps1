#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaXESmartReplay",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
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
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Creates a smart replay object" {
        It "Returns the object with all of the correct properties" {
            $splatReplay = @{
                SqlInstance = $TestConfig.instance2
                Database    = "tempdb"
                Event       = "sql_batch_completed"
                Filter      = "duration > 10000"
            }
            $results = New-DbaXESmartReplay @splatReplay
            $results.ServerName | Should -Be $TestConfig.instance2
            $results.DatabaseName | Should -Be "tempdb"
            $results.Password | Should -Be $null
            $results.Events | Should -Contain "sql_batch_completed"
            $results.Filter | Should -Be "duration > 10000"
            $results.StopOnError | Should -Be $false
        }
    }
}
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "New-DbaXESmartTableWriter",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Table",
                "AutoCreateTargetTable",
                "UploadIntervalSeconds",
                "Event",
                "OutputColumn",
                "Filter",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Create test database for table writer
        $testDb = "dbatoolsci_xetablewriter_$(Get-Random)"
        $testTable = "xe_events_test"

        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $testDb

        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $testDb -Confirm:$false
    }

    Context "Creates a smart table writer object" {
        It "Returns the object with all of the correct properties" {
            $splatTableWriter = @{
                SqlInstance = $TestConfig.instance2
                Database    = $testDb
                Table       = $testTable
            }
            $results = New-DbaXESmartTableWriter @splatTableWriter
            $results | Should -Not -BeNullOrEmpty
            $results.GetType().Name | Should -Be "TableAppenderResponse"
        }
    }
}
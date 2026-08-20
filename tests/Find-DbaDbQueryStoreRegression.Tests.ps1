#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Find-DbaDbQueryStoreRegression" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Find-DbaDbQueryStoreRegression
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "BaselineStartDaysAgo",
                "BaselineEndDaysAgo",
                "SlowdownThreshold",
                "MinExecutionCount",
                "MinTotalDurationMs",
                "EnableException"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Find-DbaDbQueryStoreRegression" -Tag "IntegrationTests" {
    BeforeAll {
        # Integration tests require a SQL Server 2016+ instance with Query Store enabled
        # and workload history. These run in the dbatools CI environment against the
        # configured test instances ($TestConfig.instance2 / instance3).
    }

    Context "Command returns expected object shape" {
        It "Returns objects with a SlowdownFactor property when regressions exist" -Skip {
            # Skipped in the template; enable against an instance with a known regression.
            $results = Find-DbaDbQueryStoreRegression -SqlInstance $TestConfig.instance2 -Database tempdb
            $results | Should -Not -BeNullOrEmpty
            $results[0].PSObject.Properties.Name | Should -Contain "SlowdownFactor"
        }
    }
}

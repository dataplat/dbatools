#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbQueryStoreOption",
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
                "ExcludeDatabase",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $testDbName = "dbatoolsci_querystoreopt_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $testDbName
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $testDbName -Query "ALTER DATABASE [$testDbName] SET QUERY_STORE = ON;"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $result = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database $testDbName
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testDbName -Confirm:$false -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.QueryStoreOptions"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ActualState",
                "DataFlushIntervalInSeconds",
                "StatisticsCollectionIntervalInMinutes",
                "MaxStorageSizeInMB",
                "CurrentStorageSizeInMB",
                "QueryCaptureMode",
                "SizeBasedCleanupMode",
                "StaleQueryThresholdInDays"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has version-specific properties for SQL 2017+" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            if ($server.VersionMajor -lt 14) { Set-ItResult -Skipped -Because "SQL Server version is below 2017" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Contain "MaxPlansPerQuery" -Because "SQL 2017+ should include MaxPlansPerQuery"
            $defaultProps | Should -Contain "WaitStatsCaptureMode" -Because "SQL 2017+ should include WaitStatsCaptureMode"
        }
    }
}
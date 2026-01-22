#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaMaxDop",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $testDbName = "dbatoolsci_testMaxDop"
        $server.Query("CREATE DATABASE dbatoolsci_testMaxDop")
        $testDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testDbName
        $setupSuccessful = $true
        if (-not $testDb) {
            $setupSuccessful = $false
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testDbName | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    # Just not messin with this in appveyor
    Context "Command works on SQL Server 2016 or higher instances" {
        BeforeAll {
            if ($setupSuccessful) {
                $testResults = Test-DbaMaxDop -SqlInstance $TestConfig.InstanceSingle
            }
        }

        It "Should have correct properties" -Skip:(-not $setupSuccessful) {
            $expectedProps = "ComputerName", "InstanceName", "SqlInstance", "Database", "DatabaseMaxDop", "CurrentInstanceMaxDop", "RecommendedMaxDop", "Notes"
            foreach ($result in $testResults) {
                ($result.PSStandardMembers.DefaultDIsplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
            }
        }

        It "Should have only one result for database name of dbatoolsci_testMaxDop" -Skip:(-not $setupSuccessful) {
            @($testResults | Where-Object Database -eq $testDbName).Count | Should -Be 1
        }
    }

    Context "Output Validation" {
        BeforeAll {
            if ($setupSuccessful) {
                $result = Test-DbaMaxDop -SqlInstance $TestConfig.InstanceSingle -EnableException
                $instanceResult = $result | Where-Object { $_.Database -eq "N/A" } | Select-Object -First 1
            }
        }

        It "Returns PSCustomObject" -Skip:(-not $setupSuccessful) {
            $instanceResult.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" -Skip:(-not $setupSuccessful) {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "DatabaseMaxDop",
                "CurrentInstanceMaxDop",
                "RecommendedMaxDop",
                "Notes"
            )
            $actualProps = $instanceResult.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the expected additional properties" -Skip:(-not $setupSuccessful) {
            $additionalProps = @(
                "InstanceVersion",
                "NumaNodes",
                "NumberOfCores"
            )
            $actualProps = $instanceResult.PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be accessible via Select-Object *"
            }
        }

        It "Returns database-level results for SQL Server 2016+" -Skip:(-not $setupSuccessful) {
            $dbResult = $result | Where-Object { $_.Database -eq $testDbName }
            if ($server.VersionMajor -ge 13) {
                $dbResult | Should -Not -BeNullOrEmpty -Because "SQL 2016+ should return database-level MaxDop results"
                $dbResult.DatabaseMaxDop | Should -Not -Be "N/A" -Because "Database-level MaxDop should be a numeric value"
            }
        }
    }
}
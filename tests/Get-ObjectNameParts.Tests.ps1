#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-ObjectNameParts",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ObjectName"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Test one part names" {
        BeforeAll {
            $objectNames = @("table1", "[table2]", "[tab..le3]", "[table]]x4]", "[table5]]]")
            $expectedTables = @("table1", "table2", "tab..le3", "table]]x4", "table5]]")
        }

        It "Should return correct parts" {
            for ($i = 0; $i -lt $objectNames.Count; $i++) {
                $result = Get-ObjectNameParts -ObjectName $objectNames[$i]
                $result.Parsed | Should -Be $true
                $result.Database | Should -Be $null
                $result.Schema | Should -Be $null
                $result.Name | Should -Be $expectedTables[$i]
            }
        }
    }

    Context "Test two part names" {
        BeforeAll {
            $objectNames = @("schema1.table1", "[sche..ma2].[table2]", "schema3.[tab..le3]", "[schema4].[table]]x4]", "schema5.[table5]]]")
            $expectedTables = @("table1", "table2", "tab..le3", "table]]x4", "table5]]")
            $expectedSchemas = @("schema1", "sche..ma2", "schema3", "schema4", "schema5")
        }

        It "Should return correct parts" {
            for ($i = 0; $i -lt $objectNames.Count; $i++) {
                $result = Get-ObjectNameParts -ObjectName $objectNames[$i]
                $result.Parsed | Should -Be $true
                $result.Database | Should -Be $null
                $result.Schema | Should -Be $expectedSchemas[$i]
                $result.Name | Should -Be $expectedTables[$i]
            }
        }
    }

    Context "Test three part names" {
        BeforeAll {
            $objectNames = @("database1.schema1.table1", "database2..table2", "database3..[tab..le3]", "db4.[sche..ma4].table4")
            $expectedTables = @("table1", "table2", "tab..le3", "table4")
            $expectedSchemas = @("schema1", $null, $null, "sche..ma4")
            $expectedDatabases = @("database1", "database2", "database3", "db4")
        }

        It "Should return correct parts" {
            for ($i = 0; $i -lt $objectNames.Count; $i++) {
                $result = Get-ObjectNameParts -ObjectName $objectNames[$i]
                $result.Parsed | Should -Be $true
                $result.Database | Should -Be $expectedDatabases[$i]
                $result.Schema | Should -Be $expectedSchemas[$i]
                $result.Name | Should -Be $expectedTables[$i]
            }
        }
    }

    Context "Test wrong names" {
        It "Should not return parts for 'part1.part2.part3.part4'" {
            (Get-ObjectNameParts -ObjectName "part1.part2.part3.part4").Parsed | Should -Be $false
        }
    }
}
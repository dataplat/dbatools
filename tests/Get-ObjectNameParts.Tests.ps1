#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-ObjectNameParts",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig
. "$PSScriptRoot\..\private\functions\Get-DirectoryRestoreFile.ps1"

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
            $objectNameInput = @("table1", "[table2]", "[tab..le3]", "[table]]x4]", "[table5]]]")
            $tableExpected = @("table1", "table2", "tab..le3", "table]]x4", "table5]]")
        }

        It "Should return correct parts" {
            for ($i = 0; $i -lt $objectNameInput.Count; $i++) {
                $result = Get-ObjectNameParts -ObjectName $objectNameInput[$i]
                $result.Parsed | Should -Be $true
                $result.Database | Should -Be $null
                $result.Schema | Should -Be $null
                $result.Name | Should -Be $tableExpected[$i]
            }
        }
    }
    Context "Test two part names" {
        BeforeAll {
            $objectNameInput = @("schema1.table1", "[sche..ma2].[table2]", "schema3.[tab..le3]", "[schema4].[table]]x4]", "schema5.[table5]]]")
            $tableExpected = @("table1", "table2", "tab..le3", "table]]x4", "table5]]")
            $schemaExpected = @("schema1", "sche..ma2", "schema3", "schema4", "schema5")
        }

        It "Should return correct parts" {
            for ($i = 0; $i -lt $objectNameInput.Count; $i++) {
                $result = Get-ObjectNameParts -ObjectName $objectNameInput[$i]
                $result.Parsed | Should -Be $true
                $result.Database | Should -Be $null
                $result.Schema | Should -Be $schemaExpected[$i]
                $result.Name | Should -Be $tableExpected[$i]
            }
        }
    }
    Context "Test three part names" {
        BeforeAll {
            $objectNameInput = @("database1.schema1.table1", "database2..table2", "database3..[tab..le3]", "db4.[sche..ma4].table4")
            $tableExpected = @("table1", "table2", "tab..le3", "table4")
            $schemaExpected = @("schema1", $null, $null, "sche..ma4")
            $databaseExpected = @("database1", "database2", "database3", "db4")
        }

        It "Should return correct parts" {
            for ($i = 0; $i -lt $objectNameInput.Count; $i++) {
                $result = Get-ObjectNameParts -ObjectName $objectNameInput[$i]
                $result.Parsed | Should -Be $true
                $result.Database | Should -Be $databaseExpected[$i]
                $result.Schema | Should -Be $schemaExpected[$i]
                $result.Name | Should -Be $tableExpected[$i]
            }
        }
    }
    Context "Test wrong names" {
        It "Should not return parts for 'part1.part2.part3.part4'" {
            (Get-ObjectNameParts -ObjectName "part1.part2.part3.part4").Parsed | Should -Be $false
        }
    }
}
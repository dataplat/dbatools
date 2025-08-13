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
            $hasParameters = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
            $expectedParameters = @('ObjectName')
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Test one part names" {
        BeforeAll {
            $objectName = @("table1", "[table2]", "[tab..le3]", "[table]]x4]", "[table5]]]")
            $table = @("table1", "table2", "tab..le3", "table]]x4", "table5]]")
        }

        It "Should return correct parts" {
            for ($i = 0; $i -lt $objectName.Count; $i++) {
                $result = Get-ObjectNameParts -ObjectName $objectName[$i]
                $result.Parsed | Should -Be $true
                $result.Database | Should -Be $null
                $result.Schema | Should -Be $null
                $result.Name | Should -Be $table[$i]
            }
        }
    }

    Context "Test two part names" {
        BeforeAll {
            $objectName = @("schema1.table1", "[sche..ma2].[table2]", "schema3.[tab..le3]", "[schema4].[table]]x4]", "schema5.[table5]]]")
            $table = @("table1", "table2", "tab..le3", "table]]x4", "table5]]")
            $schema = @("schema1", "sche..ma2", "sche ma3", "schema4", "schema5")
        }

        It "Should return correct parts" {
            for ($i = 0; $i -lt $objectName.Count; $i++) {
                $result = Get-ObjectNameParts -ObjectName $objectName[$i]
                $result.Parsed | Should -Be $true
                $result.Database | Should -Be $null
                $result.Schema | Should -Be $schema[$i]
                $result.Name | Should -Be $table[$i]
            }
        }
    }

    Context "Test three part names" {
        BeforeAll {
            $objectName = @("database1.schema1.table1", "database2..table2", "database3..[tab..le3]", "db4.[sche..ma4].table4")
            $table = @("table1", "table2", "tab..le3", "table4")
            $schema = @("schema1", $null, $null, "sche..ma4")
            $database = @("database1", "database2", "database3", "db4")
        }

        It "Should return correct parts" {
            for ($i = 0; $i -lt $objectName.Count; $i++) {
                $result = Get-ObjectNameParts -ObjectName $objectName[$i]
                $result.Parsed | Should -Be $true
                $result.Database | Should -Be $database[$i]
                $result.Schema | Should -Be $schema[$i]
                $result.Name | Should -Be $table[$i]
            }
        }
    }

    Context "Test wrong names" {
        It "Should not return parts for 'part1.part2.part3.part4'" {
            (Get-ObjectNameParts -ObjectName "part1.part2.part3.part4").Parsed | Should -Be $false
        }
    }
}
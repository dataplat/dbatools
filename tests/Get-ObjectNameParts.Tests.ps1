#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-ObjectNameParts",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

. "$PSScriptRoot\..\private\functions\Get-ObjectNameParts.ps1"

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command $CommandName
            $hasParameters = $command.Parameters.Keys | Where-Object { $PSItem -notin ("whatif", "confirm") }
            $expectedParameters = @(
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
        It "Should return correct parts" {
            $objectName = "table1", "[table2]", "[tab..le3]", "[table]]x4]", "[table5]]]"
            $table = "table1", "table2", "tab..le3", "table]x4", "table5]"
            for ($i = 0; $i -lt $objectName.Count; $i++) {
                $result = Get-ObjectNameParts -ObjectName $objectName[$i]
                $result.Parsed | Should -Be $true
                $result.Database | Should -BeNull
                $result.Schema | Should -BeNull
                $result.Name | Should -Be $table[$i]
            }
        }
    }
    Context "Test two part names" {
        It "Should return correct parts" {
            $objectName = "schema1.table1", "[sche..ma2].[table2]", "[sche ma3].[tab..le3]", "[schema4].[table]]x4]", "schema5.[table5]]]"
            $table = "table1", "table2", "tab..le3", "table]x4", "table5]"
            $schema = "schema1", "sche..ma2", "sche ma3", "schema4", "schema5"
            for ($i = 0; $i -lt $objectName.Count; $i++) {
                $result = Get-ObjectNameParts -ObjectName $objectName[$i]
                $result.Parsed | Should -Be $true
                $result.Database | Should -BeNull
                $result.Schema | Should -Be $schema[$i]
                $result.Name | Should -Be $table[$i]
            }
        }
    }
    Context "Test three part names" {
        It "Should return correct parts" {
            $objectName = "database1.schema1.table1", "database2..table2", "database3..[tab..le3]", "db4.[sche..ma4].table4"
            $table = "table1", "table2", "tab..le3", "table4"
            $schema = "schema1", $null, $null, "sche..ma4"
            $database = "database1", "database2", "database3", "db4"
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
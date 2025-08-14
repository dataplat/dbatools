#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "New-DbaSqlParameter",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "CompareInfo",
                "DbType",
                "Direction",
                "ForceColumnEncryption",
                "IsNullable",
                "LocaleId",
                "Offset",
                "ParameterName",
                "Precision",
                "Scale",
                "Size",
                "SourceColumn",
                "SourceColumnNullMapping",
                "SourceVersion",
                "SqlDbType",
                "SqlValue",
                "TypeName",
                "UdtTypeName",
                "Value",
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
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database tempdb -Query "CREATE OR ALTER PROC [dbo].[my_proc]
        @json_result nvarchar(max) output
            AS
            BEGIN
            set @json_result = (
                select 'sample' as 'example'
                for json path, without_array_wrapper
            );
            END"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup created objects.
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database tempdb -Query "DROP PROCEDURE dbo.my_proc" -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }
    It "creates a usable sql parameter" {
        $output = New-DbaSqlParameter -ParameterName json_result -SqlDbType NVarChar -Size -1 -Direction Output
        Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database tempdb -CommandType StoredProcedure -Query my_proc -SqlParameters $output
        $output.Value | Should -Be "{""example"":""sample""}"
    }
    It "binds a ""falsy"" value properly (see #9542)" {
        [int]$ZeroInt = 0
        $ZeroSqlParam = New-DbaSqlParameter -ParameterName ZeroInt -Value $ZeroInt -SqlDbType int
        $ZeroSqlParam.Value | Should -Be 0
    }
}
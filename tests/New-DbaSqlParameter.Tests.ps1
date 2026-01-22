#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaSqlParameter",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
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
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Query "CREATE OR ALTER PROC [dbo].[my_proc]
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
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Query "DROP PROCEDURE dbo.my_proc" -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Output Validation" {
        BeforeAll {
            $result = New-DbaSqlParameter -ParameterName "@TestParam" -SqlDbType NVarChar -Size 100 -Value "TestValue" -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.Data.SqlClient.SqlParameter]
        }

        It "Has the expected properties available" {
            $expectedProps = @(
                'CompareInfo',
                'DbType',
                'Direction',
                'ForceColumnEncryption',
                'IsNullable',
                'LocaleId',
                'Offset',
                'ParameterName',
                'Precision',
                'Scale',
                'Size',
                'SourceColumn',
                'SourceColumnNullMapping',
                'SourceVersion',
                'SqlDbType',
                'SqlValue',
                'TypeName',
                'UdtTypeName',
                'Value'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available on SqlParameter"
            }
        }
    }
    It "creates a usable sql parameter" {
        $output = New-DbaSqlParameter -ParameterName json_result -SqlDbType NVarChar -Size -1 -Direction Output
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database tempdb -CommandType StoredProcedure -Query my_proc -SqlParameters $output
        $output.Value | Should -Be "{""example"":""sample""}"
    }
    It "binds a ""falsy"" value properly (see #9542)" {
        [int]$ZeroInt = 0
        $ZeroSqlParam = New-DbaSqlParameter -ParameterName ZeroInt -Value $ZeroInt -SqlDbType int
        $ZeroSqlParam.Value | Should -Be 0
    }
}
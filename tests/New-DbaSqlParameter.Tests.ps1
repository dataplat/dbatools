param($ModuleName = 'dbatools')

Describe "New-DbaSqlParameter" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaSqlParameter
        }
        $requiredParameters = @(
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
        It "has the required parameter: <_>" -ForEach $requiredParameters {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "New-DbaSqlParameter Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . (Join-Path $PSScriptRoot 'constants.ps1')
    }

    BeforeAll {
        $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Database tempdb -Query "CREATE OR ALTER PROC [dbo].[my_proc]
        @json_result nvarchar(max) output
            AS
            BEGIN
            set @json_result = (
                select 'sample' as 'example'
                for json path, without_array_wrapper
            );
            END"
    }

    AfterAll {
        try {
            $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Database tempdb -Query "DROP PROCEDURE dbo.my_proc"
        } catch {
            $null = 1
        }
    }

    It "creates a usable sql parameter" {
        $output = New-DbaSqlParameter -ParameterName json_result -SqlDbType Microsoft.Data.SqlClient.SqlDbType.NVarChar -Size -1 -Direction Output
        Invoke-DbaQuery -SqlInstance $global:instance2 -Database tempdb -CommandType StoredProcedure -Query my_proc -SqlParameters $output
        $output.Value | Should -Be '{"example":"sample"}'
    }
}

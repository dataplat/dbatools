param($ModuleName = 'dbatools')

Describe "New-DbaSqlParameter" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaSqlParameter
        }
        It "Should have CompareInfo as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter CompareInfo
        }
        It "Should have DbType as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter DbType
        }
        It "Should have Direction as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Direction
        }
        It "Should have ForceColumnEncryption as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ForceColumnEncryption
        }
        It "Should have IsNullable as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter IsNullable
        }
        It "Should have LocaleId as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter LocaleId
        }
        It "Should have Offset as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Offset
        }
        It "Should have ParameterName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ParameterName
        }
        It "Should have Precision as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Precision
        }
        It "Should have Scale as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Scale
        }
        It "Should have Size as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Size
        }
        It "Should have SourceColumn as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SourceColumn
        }
        It "Should have SourceColumnNullMapping as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SourceColumnNullMapping
        }
        It "Should have SourceVersion as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SourceVersion
        }
        It "Should have SqlDbType as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlDbType
        }
        It "Should have SqlValue as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlValue
        }
        It "Should have TypeName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter TypeName
        }
        It "Should have UdtTypeName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter UdtTypeName
        }
        It "Should have Value as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Value
        }
        It "Should have EnableException as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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

param($ModuleName = 'dbatools')

Describe "New-DbaSqlParameter" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaSqlParameter
        }
        It "Should have CompareInfo as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter CompareInfo -Type String -Not -Mandatory
        }
        It "Should have DbType as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter DbType -Type String -Not -Mandatory
        }
        It "Should have Direction as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Direction -Type String -Not -Mandatory
        }
        It "Should have ForceColumnEncryption as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter ForceColumnEncryption -Type SwitchParameter -Not -Mandatory
        }
        It "Should have IsNullable as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter IsNullable -Type SwitchParameter -Not -Mandatory
        }
        It "Should have LocaleId as a non-mandatory Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter LocaleId -Type Int32 -Not -Mandatory
        }
        It "Should have Offset as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Offset -Type String -Not -Mandatory
        }
        It "Should have ParameterName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter ParameterName -Type String -Not -Mandatory
        }
        It "Should have Precision as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Precision -Type String -Not -Mandatory
        }
        It "Should have Scale as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Scale -Type String -Not -Mandatory
        }
        It "Should have Size as a non-mandatory Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter Size -Type Int32 -Not -Mandatory
        }
        It "Should have SourceColumn as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter SourceColumn -Type String -Not -Mandatory
        }
        It "Should have SourceColumnNullMapping as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter SourceColumnNullMapping -Type SwitchParameter -Not -Mandatory
        }
        It "Should have SourceVersion as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter SourceVersion -Type String -Not -Mandatory
        }
        It "Should have SqlDbType as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter SqlDbType -Type String -Not -Mandatory
        }
        It "Should have SqlValue as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter SqlValue -Type String -Not -Mandatory
        }
        It "Should have TypeName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter TypeName -Type String -Not -Mandatory
        }
        It "Should have UdtTypeName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter UdtTypeName -Type String -Not -Mandatory
        }
        It "Should have Value as a non-mandatory Object parameter" {
            $CommandUnderTest | Should -HaveParameter Value -Type Object -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }
}

Describe "New-DbaSqlParameter Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . (Join-Path $PSScriptRoot 'constants.ps1')
    }

    BeforeAll {
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database tempdb -Query "CREATE OR ALTER PROC [dbo].[my_proc]
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
            $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database tempdb -Query "DROP PROCEDURE dbo.my_proc"
        } catch {
            $null = 1
        }
    }

    It "creates a usable sql parameter" {
        $output = New-DbaSqlParameter -ParameterName json_result -SqlDbType NVarChar -Size -1 -Direction Output
        Invoke-DbaQuery -SqlInstance $script:instance2 -Database tempdb -CommandType StoredProcedure -Query my_proc -SqlParameters $output
        $output.Value | Should -Be '{"example":"sample"}'
    }
}

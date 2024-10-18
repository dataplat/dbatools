param($ModuleName = 'dbatools')

Describe "New-DbaSqlParameter" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaSqlParameter
        }
        It "Should have CompareInfo as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter CompareInfo -Type System.String -Mandatory:$false
        }
        It "Should have DbType as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter DbType -Type System.String -Mandatory:$false
        }
        It "Should have Direction as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Direction -Type System.String -Mandatory:$false
        }
        It "Should have ForceColumnEncryption as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter ForceColumnEncryption -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have IsNullable as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter IsNullable -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have LocaleId as a non-mandatory System.Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter LocaleId -Type System.Int32 -Mandatory:$false
        }
        It "Should have Offset as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Offset -Type System.String -Mandatory:$false
        }
        It "Should have ParameterName as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter ParameterName -Type System.String -Mandatory:$false
        }
        It "Should have Precision as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Precision -Type System.String -Mandatory:$false
        }
        It "Should have Scale as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Scale -Type System.String -Mandatory:$false
        }
        It "Should have Size as a non-mandatory System.Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter Size -Type System.Int32 -Mandatory:$false
        }
        It "Should have SourceColumn as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter SourceColumn -Type System.String -Mandatory:$false
        }
        It "Should have SourceColumnNullMapping as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter SourceColumnNullMapping -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have SourceVersion as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter SourceVersion -Type System.String -Mandatory:$false
        }
        It "Should have SqlDbType as a non-mandatory Microsoft.Data.SqlClient.SqlDbType parameter" {
            $CommandUnderTest | Should -HaveParameter SqlDbType -Type Microsoft.Data.SqlClient.SqlDbType -Mandatory:$false
        }
        It "Should have SqlValue as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter SqlValue -Type System.String -Mandatory:$false
        }
        It "Should have TypeName as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter TypeName -Type System.String -Mandatory:$false
        }
        It "Should have UdtTypeName as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter UdtTypeName -Type System.String -Mandatory:$false
        }
        It "Should have Value as a non-mandatory System.Object parameter" {
            $CommandUnderTest | Should -HaveParameter Value -Type System.Object -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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

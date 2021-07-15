$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'CompareInfo', 'DbType', 'Direction', 'ForceColumnEncryption', 'IsNullable', 'LocaleId', 'Offset', 'ParameterName', 'Precision', 'Scale', 'Size', 'SourceColumn', 'SourceColumnNullMapping', 'SourceVersion', 'SqlDbType', 'SqlValue', 'TypeName', 'UdtTypeName', 'Value', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
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
            $null = $db.Query("DROP PROCEDURE dbo.my_proc")
        } catch {
            $null = 1
        }
    }
    It "creates a usable sql parameter" {
        $output = New-DbaSqlParameter -ParameterName json_result -SqlDbType NVarChar -Size -1 -Direction Output
        Invoke-DbaQuery -SqlInstance localhost -Database master -CommandType StoredProcedure -Query my_proc -SqlParameters $output
        $output.Value | Should -Be '{"example":"sample"}'
    }
}
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Path', 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'Schema', 'Truncate', 'Delimiter', 'SingleColumn', 'BatchSize', 'NotifyAfter', 'TableLock', 'CheckConstraints', 'FireTriggers', 'KeepIdentity', 'KeepNulls', 'Column', 'ColumnMap', 'KeepOrdinalOrder', 'AutoCreateTable', 'NoProgress', 'NoHeaderRow', 'UseFileNameForSchema', 'Quote', 'Escape', 'Comment', 'TrimmingOption', 'BufferSize', 'ParseErrorAction', 'Encoding', 'NullValue', 'MaxQuotedFieldLength', 'SkipEmptyLine', 'SupportsMultiline', 'UseColumnDefault', 'EnableException', 'NoTransaction'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    AfterAll {
        Invoke-DbaQuery -SqlInstance $script:instance1, $script:instance2 -Database tempdb -Query "drop table SuperSmall"
    }

    $path = "$script:appveyorlabrepo\csv\SuperSmall.csv"

    Context "Works as expected" {
        $results = $path | Import-DbaCsv -SqlInstance $script:instance1 -Database tempdb -Delimiter `t -NotifyAfter 50000 -WarningVariable warn
        It "accepts piped input and doesn't add rows if the table does not exist" {
            $results | Should -Be $null
        }

        if (-not $env:appveyor) {
            $results = Import-DbaCsv -Path $path, $path -SqlInstance $script:instance1, $script:instance2 -Database tempdb -Delimiter `t -NotifyAfter 50000 -WarningVariable warn2 -AutoCreateTable

            It "performs 4 imports" {
                ($results).Count | Should -Be 4
            }

            foreach ($result in $results) {
                It "returns the good stuff" {
                    $result.RowsCopied | Should -Be 999
                    $result.Database | Should -Be tempdb
                    $result.Table | Should -Be SuperSmall
                }
            }

            $result = Import-DbaCsv -Path $path -SqlInstance $script:instance1 -Database tempdb -Delimiter `t -Table SuperSmall -Truncate
            It "doesn't break when truncate is passed" {
                $result.RowsCopied | Should -Be 999
                $result.Database | Should -Be tempdb
                $result.Table | Should -Be SuperSmall
            }

            $result = Import-DbaCsv -Path $path -SqlInstance $script:instance1 -Database tempdb -Delimiter `t -Table SuperSmall -Truncate -NoTransaction
            It "works with NoTransaction" {
                $result.RowsCopied | Should -Be 999
                $result.Database | Should -Be tempdb
                $result.Table | Should -Be SuperSmall
            }
        }
    }
}
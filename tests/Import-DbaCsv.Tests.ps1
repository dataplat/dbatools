$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Import-DbaCsv).Parameters.Keys
        $knownParameters = 'Path', 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'Schema', 'Truncate', 'Delimiter', 'SingleColumn', 'BatchSize', 'NotifyAfter', 'TableLock', 'CheckConstraints', 'FireTriggers', 'KeepIdentity', 'KeepNulls', 'Column', 'ColumnMap', 'AutoCreateTable', 'NoProgress', 'NoHeaderRow', 'Quote', 'Escape', 'Comment', 'TrimmingOption', 'BufferSize', 'ParseErrorAction', 'Encoding', 'NullValue', 'Threshold', 'MaxQuotedFieldLength', 'SkipEmptyLine', 'SupportsMultiline', 'UseColumnDefault', 'EnableException'
        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $knownParameters.Count
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
            $resulst | Should -Be $null
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
        }
    }
}
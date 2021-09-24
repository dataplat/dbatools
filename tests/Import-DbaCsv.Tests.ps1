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

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    AfterAll {
        Invoke-DbaQuery -SqlInstance $script:instance1, $script:instance2 -Database tempdb -Query "drop table SuperSmall"
    }

    $path = "$script:appveyorlabrepo\csv\SuperSmall.csv"
    $CommaSeparatedWithHeader = "$script:appveyorlabrepo\csv\CommaSeparatedWithHeader.csv"
    $col1 = "$script:appveyorlabrepo\csv\cols.csv"
    $col2 = "$script:appveyorlabrepo\csv\col2.csv"
    $pipe3 = "$script:appveyorlabrepo\csv\pipe3.psv"


    Context "Works as expected" {
        $results = $path | Import-DbaCsv -SqlInstance $script:instance1 -Database tempdb -Delimiter `t -NotifyAfter 50000 -WarningVariable warn
        It "accepts piped input and doesn't add rows if the table does not exist" {
            $results | Should -Be $null
        }

        It "creates the right columnmap (#7630), handles pipe delimiters (#7806)" {
            $null = Import-DbaCsv -SqlInstance $script:instance1 -Path $col1 -Database tempdb -AutoCreateTable -Table cols
            $null = Import-DbaCsv -SqlInstance $script:instance1 -Path $col2 -Database tempdb -Table cols
            $null = Import-DbaCsv -SqlInstance $script:instance1 -Path $pipe3 -Database tempdb -Table cols -Delimiter "|"
            $results = Invoke-DbaQuery -SqlInstance $script:instance1 -Database tempdb -Query "select * from cols"
            $results | Where-Object third -notmatch "three" | Should -BeNullOrEmpty
            $results | Where-Object firstcol -notmatch "one" | Should -BeNullOrEmpty
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

        It "Catches the scenario where the database param does not match the server object passed into the command" {
            $server = Connect-DbaInstance $script:instance1 -Database tempdb
            $result = Import-DbaCsv -Path $path -SqlInstance $server -Database InvalidDB -Delimiter `t -Table SuperSmall -Truncate -AutoCreateTable
            $result | Should -BeNullOrEmpty

            $server = Connect-DbaInstance $script:instance1 -Database tempdb
            $result = Import-DbaCsv -Path $path -SqlInstance $server -Database tempdb -Delimiter `t -Table SuperSmall -Truncate -AutoCreateTable
            $result.RowsCopied | Should -Be 999
            $result.Database | Should -Be tempdb
            $result.Table | Should -Be SuperSmall
        }

        It "Catches the scenario where the header is not properly parsed causing param errors" {
            # create the table using AutoCreate
            $server = Connect-DbaInstance $script:instance1 -Database tempdb
            $null = Import-DbaCsv -Path $CommaSeparatedWithHeader -SqlInstance $server -Database tempdb -AutoCreateTable

            # reload table without AutoCreate parameter to recreate bug #6553
            $result = Import-DbaCsv -Path $CommaSeparatedWithHeader -SqlInstance $server -Database tempdb -Truncate
            $result.RowsCopied | Should -Be 1
            $result.Database | Should -Be tempdb
            $result.Table | Should -Be CommaSeparatedWithHeader
        }
    }
}
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

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
    BeforeAll {
        $pathSuperSmall = "$($TestConfig.appveyorlabrepo)\csv\SuperSmall.csv"
        $pathCommaSeparatedWithHeader = "$($TestConfig.appveyorlabrepo)\csv\CommaSeparatedWithHeader.csv"
        $pathCols = "$($TestConfig.appveyorlabrepo)\csv\cols.csv"
        $pathCol2 = "$($TestConfig.appveyorlabrepo)\csv\col2.csv"
        $pathPipe3 = "$($TestConfig.appveyorlabrepo)\csv\pipe3.psv"
    }

    AfterAll {
        Get-DbaDbTable -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -Database tempdb -Table SuperSmall, CommaSeparatedWithHeader | Remove-DbaDbTable -Confirm:$false
    }

    Context "Works as expected" {
        It "accepts piped input and doesn't add rows if the table does not exist" {
            $results = $pathSuperSmall | Import-DbaCsv -SqlInstance $TestConfig.instance1 -Database tempdb -Delimiter `t -NotifyAfter 50000 -WarningVariable WarnVar -WarningAction SilentlyContinue

            $WarnVar | Should -BeLike "*Table or view SuperSmall does not exist and AutoCreateTable was not specified*"
            $results | Should -BeNullOrEmpty
        }

        It "creates the right columnmap (#7630), handles pipe delimiters (#7806)" {
            $null = Import-DbaCsv -SqlInstance $TestConfig.instance1 -Path $pathCols -Database tempdb -AutoCreateTable -Table cols
            $null = Import-DbaCsv -SqlInstance $TestConfig.instance1 -Path $pathCol2 -Database tempdb -Table cols
            $null = Import-DbaCsv -SqlInstance $TestConfig.instance1 -Path $pathPipe3 -Database tempdb -Table cols2 -Delimiter "|" -AutoCreateTable


            $results = Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database tempdb -Query "select * from cols"

            $results | Where-Object third -notmatch "three" | Should -BeNullOrEmpty
            $results | Where-Object firstcol -notmatch "one" | Should -BeNullOrEmpty


            $results = Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database tempdb -Query "select * from cols2"

            $results | Where-Object third -notmatch "three" | Should -BeNullOrEmpty
            $results | Where-Object firstcol -notmatch "one" | Should -BeNullOrEmpty
        }

        It "performs 4 imports" {
            $results = Import-DbaCsv -Path $pathSuperSmall, $pathSuperSmall -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -Database tempdb -Delimiter `t -NotifyAfter 50000 -WarningVariable warn2 -AutoCreateTable

            ($results).Count | Should -Be 4
            foreach ($result in $results) {
                $result.RowsCopied | Should -Be 999
                $result.Database | Should -Be tempdb
                $result.Table | Should -Be SuperSmall
            }
        }

        It "doesn't break when truncate is passed" {
            $result = Import-DbaCsv -Path $pathSuperSmall -SqlInstance $TestConfig.instance1 -Database tempdb -Delimiter `t -Table SuperSmall -Truncate

            $result.RowsCopied | Should -Be 999
            $result.Database | Should -Be tempdb
            $result.Table | Should -Be SuperSmall
        }

        It "works with NoTransaction" {
            $result = Import-DbaCsv -Path $pathSuperSmall -SqlInstance $TestConfig.instance1 -Database tempdb -Delimiter `t -Table SuperSmall -Truncate -NoTransaction

            $result.RowsCopied | Should -Be 999
            $result.Database | Should -Be tempdb
            $result.Table | Should -Be SuperSmall
        }

        It "Catches the scenario where the database param does not match the server object passed into the command" {
            $result = Import-DbaCsv -Path $pathSuperSmall -SqlInstance $TestConfig.instance1 -Database InvalidDB -Delimiter `t -Table SuperSmall -Truncate -AutoCreateTable -WarningVariable WarnVar  -WarningAction SilentlyContinue

            $WarnVar | Should -BeLike "*Cannot open database * requested by the login. The login failed.*"
            $result | Should -BeNullOrEmpty

            $result = Import-DbaCsv -Path $pathSuperSmall -SqlInstance $TestConfig.instance1 -Database tempdb -Delimiter `t -Table SuperSmall -Truncate -AutoCreateTable

            $result.RowsCopied | Should -Be 999
            $result.Database | Should -Be tempdb
            $result.Table | Should -Be SuperSmall
        }

        It "Catches the scenario where the header is not properly parsed causing param errors" {
            # create the table using AutoCreate
            $null = Import-DbaCsv -Path $pathCommaSeparatedWithHeader -SqlInstance $TestConfig.instance1 -Database tempdb -AutoCreateTable
            # reload table without AutoCreate parameter to recreate bug #6553
            $result = Import-DbaCsv -Path $pathCommaSeparatedWithHeader -SqlInstance $TestConfig.instance1 -Database tempdb -Truncate

            $result.RowsCopied | Should -Be 1
            $result.Database | Should -Be tempdb
            $result.Table | Should -Be CommaSeparatedWithHeader

            Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database tempdb -Query 'DROP TABLE CommaSeparatedWithHeader'
        }

        It "works with NoHeaderRow" {
            # See #7759
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            Invoke-DbaQuery -SqlInstance $server -Query 'CREATE TABLE NoHeaderRow (c1 VARCHAR(50), c2 VARCHAR(50), c3 VARCHAR(50))'

            $result = Import-DbaCsv -Path $pathCols -NoHeaderRow -SqlInstance $server -Database tempdb -Table 'NoHeaderRow'
            $data = Invoke-DbaQuery -SqlInstance $server -Query 'SELECT * FROM NoHeaderRow' -As PSObject

            $result.RowsCopied | Should -Be 3
            $data[0].c1 | Should -Be 'firstcol'

            Invoke-DbaQuery -SqlInstance $server -Query 'DROP TABLE NoHeaderRow'
        }

        It "works with tables which have non-varchar types (date)" {
            # See #9433
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            Invoke-DbaQuery -SqlInstance $server -Query 'CREATE TABLE WithTypes ([date] DATE, col1 VARCHAR(50), col2 VARCHAR(50))'
            $result = Import-DbaCsv -Path $pathCommaSeparatedWithHeader -SqlInstance $server -Database tempdb -Table 'WithTypes'

            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -Be 1

            Invoke-DbaQuery -SqlInstance $server -Query 'DROP TABLE WithTypes'
        }

        It "works with tables which have non-varchar types (guid, bit)" {
            # See #9433
            $filePath = "$($TestConfig.Temp)\foo.csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            Invoke-DbaQuery -SqlInstance $server -Query 'CREATE TABLE WithGuidsAndBits (one_guid UNIQUEIDENTIFIER, one_bit BIT)'
            $row = [pscustomobject]@{
                one_guid = (New-Guid).Guid
                one_bit  = 1
            }
            $row | Export-Csv -Path $filePath -NoTypeInformation

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table 'WithGuidsAndBits'

            $result.RowsCopied | Should -Be 1

            Invoke-DbaQuery -SqlInstance $server -Query 'DROP TABLE WithGuidsAndBits'
            Remove-Item $filePath
        }
    }
}

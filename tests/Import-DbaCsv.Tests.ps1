param($ModuleName = 'dbatools')

Describe "Import-DbaCsv" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $path = "$env:appveyorlabrepo\csv\SuperSmall.csv"
        $CommaSeparatedWithHeader = "$env:appveyorlabrepo\csv\CommaSeparatedWithHeader.csv"
        $col1 = "$env:appveyorlabrepo\csv\cols.csv"
        $col2 = "$env:appveyorlabrepo\csv\col2.csv"
        $pipe3 = "$env:appveyorlabrepo\csv\pipe3.psv"
    }

    AfterAll {
        Invoke-DbaQuery -SqlInstance $global:instance1, $global:instance2 -Database tempdb -Query "drop table SuperSmall; drop table CommaSeparatedWithHeader"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Import-DbaCsv
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "Path",
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Table",
                "Schema",
                "Truncate",
                "Delimiter",
                "SingleColumn",
                "BatchSize",
                "NotifyAfter",
                "TableLock",
                "CheckConstraints",
                "FireTriggers",
                "KeepIdentity",
                "KeepNulls",
                "Column",
                "ColumnMap",
                "KeepOrdinalOrder",
                "AutoCreateTable",
                "NoProgress",
                "NoHeaderRow",
                "UseFileNameForSchema",
                "Quote",
                "Escape",
                "Comment",
                "TrimmingOption",
                "BufferSize",
                "ParseErrorAction",
                "Encoding",
                "NullValue",
                "MaxQuotedFieldLength",
                "SkipEmptyLine",
                "SupportsMultiline",
                "UseColumnDefault",
                "NoTransaction",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        It "accepts piped input and doesn't add rows if the table does not exist" {
            $results = $path | Import-DbaCsv -SqlInstance $global:instance1 -Database tempdb -Delimiter `t -NotifyAfter 50000 -WarningVariable warn
            $results | Should -BeNullOrEmpty
        }

        It "creates the right columnmap (#7630), handles pipe delimiters (#7806)" {
            $null = Import-DbaCsv -SqlInstance $global:instance1 -Path $col1 -Database tempdb -AutoCreateTable -Table cols
            $null = Import-DbaCsv -SqlInstance $global:instance1 -Path $col2 -Database tempdb -Table cols
            $null = Import-DbaCsv -SqlInstance $global:instance1 -Path $pipe3 -Database tempdb -Table cols2 -Delimiter "|" -AutoCreateTable
            $results = Invoke-DbaQuery -SqlInstance $global:instance1 -Database tempdb -Query "select * from cols"
            $results | Where-Object third -notmatch "three" | Should -BeNullOrEmpty
            $results | Where-Object firstcol -notmatch "one" | Should -BeNullOrEmpty
            $results = Invoke-DbaQuery -SqlInstance $global:instance1 -Database tempdb -Query "select * from cols2"
            $results | Where-Object third -notmatch "three" | Should -BeNullOrEmpty
            $results | Where-Object firstcol -notmatch "one" | Should -BeNullOrEmpty
        }

        It "performs 4 imports" -Skip:($null -ne $env:appveyor) {
            $results = Import-DbaCsv -Path $path, $path -SqlInstance $global:instance1, $global:instance2 -Database tempdb -Delimiter `t -NotifyAfter 50000 -WarningVariable warn2 -AutoCreateTable
            $results.Count | Should -Be 4

            foreach ($result in $results) {
                $result.RowsCopied | Should -Be 999
                $result.Database | Should -Be tempdb
                $result.Table | Should -Be SuperSmall
            }
        }

        It "doesn't break when truncate is passed" -Skip:($null -ne $env:appveyor) {
            $result = Import-DbaCsv -Path $path -SqlInstance $global:instance1 -Database tempdb -Delimiter `t -Table SuperSmall -Truncate
            $result.RowsCopied | Should -Be 999
            $result.Database | Should -Be tempdb
            $result.Table | Should -Be SuperSmall
        }

        It "works with NoTransaction" -Skip:($null -ne $env:appveyor) {
            $result = Import-DbaCsv -Path $path -SqlInstance $global:instance1 -Database tempdb -Delimiter `t -Table SuperSmall -Truncate -NoTransaction
            $result.RowsCopied | Should -Be 999
            $result.Database | Should -Be tempdb
            $result.Table | Should -Be SuperSmall
        }

        It "Catches the scenario where the database param does not match the server object passed into the command" {
            $server = Connect-DbaInstance $global:instance1 -Database tempdb
            $result = Import-DbaCsv -Path $path -SqlInstance $server -Database InvalidDB -Delimiter `t -Table SuperSmall -Truncate -AutoCreateTable
            $result | Should -BeNullOrEmpty

            $server = Connect-DbaInstance $global:instance1 -Database tempdb
            $result = Import-DbaCsv -Path $path -SqlInstance $server -Database tempdb -Delimiter `t -Table SuperSmall -Truncate -AutoCreateTable
            $result.RowsCopied | Should -Be 999
            $result.Database | Should -Be tempdb
            $result.Table | Should -Be SuperSmall
        }

        It "Catches the scenario where the header is not properly parsed causing param errors" {
            $server = Connect-DbaInstance $global:instance1 -Database tempdb
            $null = Import-DbaCsv -Path $CommaSeparatedWithHeader -SqlInstance $server -Database tempdb -AutoCreateTable

            $result = Import-DbaCsv -Path $CommaSeparatedWithHeader -SqlInstance $server -Database tempdb -Truncate
            $result.RowsCopied | Should -Be 1
            $result.Database | Should -Be tempdb
            $result.Table | Should -Be CommaSeparatedWithHeader
            Invoke-DbaQuery -SqlInstance $server -Query 'DROP TABLE NoHeaderRow'
        }

        It "works with NoHeaderRow" {
            $server = Connect-DbaInstance $global:instance1 -Database tempdb
            Invoke-DbaQuery -SqlInstance $server -Query 'CREATE TABLE NoHeaderRow (c1 VARCHAR(50), c2 VARCHAR(50), c3 VARCHAR(50))'
            $result = Import-DbaCsv -Path $col1 -NoHeaderRow -SqlInstance $server -Database tempdb -Table 'NoHeaderRow' -WarningVariable warnNoHeaderRow
            $data = Invoke-DbaQuery -SqlInstance $server -Query 'SELECT * FROM NoHeaderRow' -As PSObject
            Invoke-DbaQuery -SqlInstance $server -Query 'DROP TABLE NoHeaderRow'

            $warnNoHeaderRow | Should -BeNullOrEmpty
            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -Be 3
            $data[0].c1 | Should -Be 'firstcol'
        }

        It "works with tables which have non-varchar types (date)" {
            $server = Connect-DbaInstance $global:instance1 -Database tempdb
            Invoke-DbaQuery -SqlInstance $server -Query 'CREATE TABLE WithTypes ([date] DATE, col1 VARCHAR(50), col2 VARCHAR(50))'
            $result = Import-DbaCsv -Path $CommaSeparatedWithHeader -SqlInstance $server -Database tempdb -Table 'WithTypes'
            Invoke-DbaQuery -SqlInstance $server -Query 'DROP TABLE WithTypes'

            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -Be 1
        }

        It "works with tables which have non-varchar types (guid, bit)" {
            $filePath = '.\foo.csv'
            $server = Connect-DbaInstance $global:instance1 -Database tempdb
            Invoke-DbaQuery -SqlInstance $server -Query 'CREATE TABLE WithGuidsAndBits (one_guid UNIQUEIDENTIFIER, one_bit BIT)'
            $row = [pscustomobject]@{
                one_guid = (New-Guid).Guid
                one_bit  = 1
            }
            $row | Export-Csv -Path $filePath -NoTypeInformation
            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table 'WithGuidsAndBits'
            Invoke-DbaQuery -SqlInstance $server -Query 'DROP TABLE WithGuidsAndBits'

            $result.RowsCopied | Should -Be 1
            Remove-Item $filePath
        }
    }
}

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
        It "Should have Path parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.Object[] -Mandatory:$false
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String -Mandatory:$false
        }
        It "Should have Table parameter" {
            $CommandUnderTest | Should -HaveParameter Table -Type System.String -Mandatory:$false
        }
        It "Should have Schema parameter" {
            $CommandUnderTest | Should -HaveParameter Schema -Type System.String -Mandatory:$false
        }
        It "Should have Truncate parameter" {
            $CommandUnderTest | Should -HaveParameter Truncate -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Delimiter parameter" {
            $CommandUnderTest | Should -HaveParameter Delimiter -Type System.Char -Mandatory:$false
        }
        It "Should have SingleColumn parameter" {
            $CommandUnderTest | Should -HaveParameter SingleColumn -Type System.Management.Automation.SwitchParameter
        }
        It "Should have BatchSize parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSize -Type System.Int32 -Mandatory:$false
        }
        It "Should have NotifyAfter parameter" {
            $CommandUnderTest | Should -HaveParameter NotifyAfter -Type System.Int32 -Mandatory:$false
        }
        It "Should have TableLock parameter" {
            $CommandUnderTest | Should -HaveParameter TableLock -Type System.Management.Automation.SwitchParameter
        }
        It "Should have CheckConstraints parameter" {
            $CommandUnderTest | Should -HaveParameter CheckConstraints -Type System.Management.Automation.SwitchParameter
        }
        It "Should have FireTriggers parameter" {
            $CommandUnderTest | Should -HaveParameter FireTriggers -Type System.Management.Automation.SwitchParameter
        }
        It "Should have KeepIdentity parameter" {
            $CommandUnderTest | Should -HaveParameter KeepIdentity -Type System.Management.Automation.SwitchParameter
        }
        It "Should have KeepNulls parameter" {
            $CommandUnderTest | Should -HaveParameter KeepNulls -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Column parameter" {
            $CommandUnderTest | Should -HaveParameter Column -Type System.String[] -Mandatory:$false
        }
        It "Should have ColumnMap parameter" {
            $CommandUnderTest | Should -HaveParameter ColumnMap -Type System.Collections.Hashtable -Mandatory:$false
        }
        It "Should have KeepOrdinalOrder parameter" {
            $CommandUnderTest | Should -HaveParameter KeepOrdinalOrder -Type System.Management.Automation.SwitchParameter
        }
        It "Should have AutoCreateTable parameter" {
            $CommandUnderTest | Should -HaveParameter AutoCreateTable -Type System.Management.Automation.SwitchParameter
        }
        It "Should have NoProgress parameter" {
            $CommandUnderTest | Should -HaveParameter NoProgress -Type System.Management.Automation.SwitchParameter
        }
        It "Should have NoHeaderRow parameter" {
            $CommandUnderTest | Should -HaveParameter NoHeaderRow -Type System.Management.Automation.SwitchParameter
        }
        It "Should have UseFileNameForSchema parameter" {
            $CommandUnderTest | Should -HaveParameter UseFileNameForSchema -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Quote parameter" {
            $CommandUnderTest | Should -HaveParameter Quote -Type System.Char -Mandatory:$false
        }
        It "Should have Escape parameter" {
            $CommandUnderTest | Should -HaveParameter Escape -Type System.Char -Mandatory:$false
        }
        It "Should have Comment parameter" {
            $CommandUnderTest | Should -HaveParameter Comment -Type System.Char -Mandatory:$false
        }
        It "Should have TrimmingOption parameter" {
            $CommandUnderTest | Should -HaveParameter TrimmingOption -Type System.String -Mandatory:$false
        }
        It "Should have BufferSize parameter" {
            $CommandUnderTest | Should -HaveParameter BufferSize -Type System.Int32 -Mandatory:$false
        }
        It "Should have ParseErrorAction parameter" {
            $CommandUnderTest | Should -HaveParameter ParseErrorAction -Type System.String -Mandatory:$false
        }
        It "Should have Encoding parameter" {
            $CommandUnderTest | Should -HaveParameter Encoding -Type System.String -Mandatory:$false
        }
        It "Should have NullValue parameter" {
            $CommandUnderTest | Should -HaveParameter NullValue -Type System.String -Mandatory:$false
        }
        It "Should have MaxQuotedFieldLength parameter" {
            $CommandUnderTest | Should -HaveParameter MaxQuotedFieldLength -Type System.Int32 -Mandatory:$false
        }
        It "Should have SkipEmptyLine parameter" {
            $CommandUnderTest | Should -HaveParameter SkipEmptyLine -Type System.Management.Automation.SwitchParameter
        }
        It "Should have SupportsMultiline parameter" {
            $CommandUnderTest | Should -HaveParameter SupportsMultiline -Type System.Management.Automation.SwitchParameter
        }
        It "Should have UseColumnDefault parameter" {
            $CommandUnderTest | Should -HaveParameter UseColumnDefault -Type System.Management.Automation.SwitchParameter
        }
        It "Should have NoTransaction parameter" {
            $CommandUnderTest | Should -HaveParameter NoTransaction -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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

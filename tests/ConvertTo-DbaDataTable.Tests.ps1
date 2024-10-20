param($ModuleName = 'dbatools')

Describe "ConvertTo-DbaDataTable" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command ConvertTo-DbaDataTable
        }

        $params = @(
            "InputObject",
            "TimeSpanType",
            "SizeType",
            "IgnoreNull",
            "Raw",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Testing data table output when using a complex object" {
        BeforeAll {
            $obj = New-Object -TypeName psobject -Property @{
                guid             = [system.guid]'32ccd4c4-282a-4c0d-997c-7b5deb97f9e0'
                timespan         = New-TimeSpan -Start 2016-10-30 -End 2017-04-30
                datetime         = Get-Date -Year 2016 -Month 10 -Day 30 -Hour 5 -Minute 52 -Second 0 -Millisecond 0
                char             = [System.Char]'T'
                true             = $true
                false            = $false
                null             = $null
                string           = "it's a boy."
                UInt64           = [System.UInt64]123456
                dbadatetime      = [dbadatetime[]]$(Get-Date -Year 2024 -Month 05 -Day 19 -Hour 5 -Minute 52 -Second 0 -Millisecond 0)
                dbadatetimeArray = [dbadatetime[]]($(Get-Date -Year 2024 -Month 05 -Day 19 -Hour 5 -Minute 52 -Second 0 -Millisecond 0), $(Get-Date -Year 2024 -Month 05 -Day 19 -Hour 5 -Minute 52 -Second 0 -Millisecond 0).AddHours(1))
                inlining         = [pscustomobject]@{Mission = 'Keep Hank alive'}
                inlining2        = [psobject]@{Mission = 'Keep Hank alive'}
            }

            $innedobj = New-Object -TypeName psobject -Property @{
                Mission = 'Keep Hank alive'
            }

            Add-Member -Force -InputObject $obj -MemberType NoteProperty -Name myObject -Value $innedobj
            $result = ConvertTo-DbaDataTable -InputObject $obj

            $firstRow = $result[0].Rows[0]
        }

        It 'Should have 1 row' {
            $result.Rows.Count | Should -Be 1
        }

        It 'Should have a guid column with correct value' {
            $result.Columns.ColumnName | Should -Contain 'guid'
            $firstRow.guid | Should -BeOfType [System.Guid]
            $firstRow.guid | Should -Be '32ccd4c4-282a-4c0d-997c-7b5deb97f9e0'
        }

        It 'Should have a timespan column with correct value' {
            $result.Columns.ColumnName | Should -Contain 'timespan'
            $firstRow.timespan | Should -BeOfType [System.Int64]
            $firstRow.timespan | Should -Be 15724800000
        }

        It 'Should have a datetime column with correct value' {
            $result.Columns.ColumnName | Should -Contain 'datetime'
            $firstRow.datetime | Should -BeOfType [System.DateTime]
            $date = Get-Date -Year 2016 -Month 10 -Day 30 -Hour 5 -Minute 52 -Second 0 -Millisecond 0
            $firstRow.datetime | Should -Be $date
        }

        It 'Should have a char column with correct value' {
            $result.Columns.ColumnName | Should -Contain 'char'
            $firstRow.char | Should -BeOfType [System.Char]
            $firstRow.char | Should -Be "T"
        }

        It 'Should have a true column with correct value' {
            $result.Columns.ColumnName | Should -Contain 'true'
            $firstRow.true | Should -BeOfType [System.Boolean]
            $firstRow.true | Should -BeTrue
        }

        It 'Should have a false column with correct value' {
            $result.Columns.ColumnName | Should -Contain 'false'
            $firstRow.false | Should -BeOfType [System.Boolean]
            $firstRow.false | Should -BeFalse
        }

        It 'Should have a null column with null value' {
            $result.Columns.ColumnName | Should -Contain 'null'
            $firstRow.null | Should -BeOfType [System.DBNull]
            $firstRow.null | Should -BeNullOrEmpty
        }

        It 'Should have a string column with correct value' {
            $result.Columns.ColumnName | Should -Contain 'string'
            $firstRow.string | Should -BeOfType [System.String]
            $firstRow.string | Should -Be "it's a boy."
        }

        It 'Should have a UInt64 column with correct value' {
            $result.Columns.ColumnName | Should -Contain 'UInt64'
            $firstRow.UInt64 | Should -BeOfType [System.UInt64]
            $firstRow.UInt64 | Should -Be 123456
        }

        It 'Should have a myObject column' {
            $result.Columns.ColumnName | Should -Contain 'myObject'
        }

        It 'Should have a dbadatetime column with correct value' {
            $result.Columns.ColumnName | Should -Contain 'dbadatetime'
            $firstRow.dbadatetime | Should -BeOfType [System.String]
            $date = Get-Date -Year 2024 -Month 5 -Day 19 -Hour 5 -Minute 52 -Second 0 -Millisecond 0
            [datetime]$result.dbadatetime | Should -Be $date
        }

        It 'Should have a dbadatetimeArray column with correct value' {
            $result.Columns.ColumnName | Should -Contain 'dbadatetimeArray'
            $firstRow.dbadatetimeArray | Should -BeOfType [System.String]
            $string = '2024-05-19 05:52:00.000, 2024-05-19 06:52:00.000'
            $firstRow.dbadatetimeArray | Should -Be $string
        }
    }

    Context "Testing input parameters" {
        BeforeAll {
            $obj = New-Object -TypeName psobject -Property @{
                timespan = New-TimeSpan -Start 2017-01-01 -End 2017-01-02
            }
        }

        It "Should return '1.00:00:00' when TimeSpanType is String" {
            (ConvertTo-DbaDataTable -InputObject $obj -TimeSpanType System.String).Timespan | Should -Be '1.00:00:00'
        }

        It "Should return 864000000000 when TimeSpanType is Ticks" {
            (ConvertTo-DbaDataTable -InputObject $obj -TimeSpanType Ticks).Timespan | Should -Be 864000000000
        }

        It "Should return 1 when TimeSpanType is TotalDays" {
            (ConvertTo-DbaDataTable -InputObject $obj -TimeSpanType TotalDays).Timespan | Should -Be 1
        }

        It "Should return 24 when TimeSpanType is TotalHours" {
            (ConvertTo-DbaDataTable -InputObject $obj -TimeSpanType TotalHours).Timespan | Should -Be 24
        }

        It "Should return 86400000 when TimeSpanType is TotalMilliseconds" {
            (ConvertTo-DbaDataTable -InputObject $obj -TimeSpanType TotalMilliseconds).Timespan | Should -Be 86400000
        }

        It "Should return 1440 when TimeSpanType is TotalMinutes" {
            (ConvertTo-DbaDataTable -InputObject $obj -TimeSpanType TotalMinutes).Timespan | Should -Be 1440
        }

        It "Should return 86400 when TimeSpanType is TotalSeconds" {
            (ConvertTo-DbaDataTable -InputObject $obj -TimeSpanType TotalSeconds).Timespan | Should -Be 86400
        }
    }

    Context "Verifying IgnoreNull" {
        BeforeAll {
            function returnnull {
                [CmdletBinding()]
                param ()
                New-Object -TypeName psobject -Property @{ Name = [int]1 }
                $null
                New-Object -TypeName psobject -Property @{ Name = [int]3 }
            }

            function returnOnlynull {
                [CmdletBinding()]
                param ()
                $null
            }
        }

        It "Does not create row if null is in array when IgnoreNull is set" {
            $result = ConvertTo-DbaDataTable -InputObject (returnnull) -IgnoreNull -WarningAction SilentlyContinue
            $result.Rows.Count | Should -Be 2
        }

        It "Does not create row if null is in pipeline when IgnoreNull is set" {
            $result = returnnull | ConvertTo-DbaDataTable -IgnoreNull -WarningAction SilentlyContinue
            $result.Rows.Count | Should -Be 2
        }

        It "Returns empty row when null value is provided (without IgnoreNull)" {
            $result = ConvertTo-DbaDataTable -InputObject (returnnull)
            $result.Name[0] | Should -Be 1
            $result.Name[1].GetType().FullName | Should -Be 'System.DBNull'
            $result.Name[2] | Should -Be 3
        }

        It "Returns empty row when null value is passed in pipe (without IgnoreNull)" {
            $result = returnnull | ConvertTo-DbaDataTable
            $result.Name[0] | Should -Be 1
            $result.Name[1].GetType().FullName | Should -Be 'System.DBNull'
            $result.Name[2] | Should -Be 3
        }
    }

    Context "Verifying EnableException" {
        BeforeAll {
            function returnnull {
                New-Object -TypeName psobject -Property @{ Name = 1 }
                $null
                New-Object -TypeName psobject -Property @{ Name = 3 }
            }
        }

        It "Suppresses warning messages when EnableException is used" {
            $null = ConvertTo-DbaDataTable -InputObject (returnnull) -IgnoreNull -EnableException -WarningVariable warn -WarningAction SilentlyContinue 3> $null
            $warn | Should -BeNullOrEmpty
        }
    }

    Context "Verifying script properties returning null" {
        It "Returns string column if a script property returns null" {
            $myobj = New-Object -TypeName psobject -Property @{ Name = 'Test' }
            $myobj | Add-Member -Force -MemberType ScriptProperty -Name ScriptNothing -Value { $null }
            $r = ConvertTo-DbaDataTable -InputObject $myobj
            ($r.Columns | Where-Object ColumnName -eq ScriptNothing | Select-Object -ExpandProperty DataType).ToString() | Should -Be 'System.String'
        }
    }

    Context "Verifying a datatable gets cloned when passed in" {
        BeforeAll {
            $obj = New-Object -TypeName psobject -Property @{
                col1 = 'col1'
                col2 = 'col2'
            }
            $first = $obj | ConvertTo-DbaDataTable
            $second = $first | ConvertTo-DbaDataTable
        }

        It "Should have the same columns" {
            $firstColumns = ($first.Columns.ColumnName | Sort-Object) -Join ','
            $secondColumns = ($second.Columns.ColumnName | Sort-Object) -Join ','
            $firstColumns | Should -Be $secondColumns
        }
    }
}

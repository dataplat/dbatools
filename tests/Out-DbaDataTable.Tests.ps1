

Describe "Testing data table output when using a complex object" {
    $obj = New-Object -TypeName psobject -Property @{
        guid = [system.guid]'32ccd4c4-282a-4c0d-997c-7b5deb97f9e0'
        timespan = New-TimeSpan -Start 2016-10-30 -End 2017-04-30
        datetime = Get-Date -Year 2016 -Month 10 -Day 30 -Hour 5 -Minute 52 -Second 0 -Millisecond 0
        char = [System.Char]'T'
        true = $true
        false = $false
        null = [bool]$null
        string = "it's a boy!"
        UInt64 = [System.UInt64]123456
    }
    $result = Out-DbaDataTable -InputObject $obj

    Context "Property: guid" {
        It 'Has a column called "guid"' {
            $result.Columns.ColumnName.Contains('guid') | Should Be $true 
        }
        It 'Has a [guid] data type on the column "guid"' {
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'guid' | Select-Object -ExpandProperty 'DataType' | Should Be 'guid'
        }
        It 'Has the following guid: "32ccd4c4-282a-4c0d-997c-7b5deb97f9e0"' {
            $result.guid | Should Be '32ccd4c4-282a-4c0d-997c-7b5deb97f9e0'
        }
    }

    Context "Property: timespan" {
        It 'Has a column called "timespan"' {
            $result.Columns.ColumnName.Contains('timespan') | Should Be $true 
        }
        It 'Has a [long] data type on the column "timespan"' {
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'timespan' | Select-Object -ExpandProperty 'DataType' | Should Be 'long'
        }
        It "Has the following timespan: 15724800000" {
            $result.timespan | Should Be 15724800000
        }
    }

    Context "Property: datetime" {
        It 'Has a column called "datetime"' {
            $result.Columns.ColumnName.Contains('datetime') | Should Be $true 
        }
        It 'Has a [datetime] data type on the column "datetime"' {
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'datetime' | Select-Object -ExpandProperty 'DataType' | Should Be 'datetime'
        }
        It "Has the following datetime: 2016-10-30 05:52:00.000" {
            $date = Get-Date -Year 2016 -Month 10 -Day 30 -Hour 5 -Minute 52 -Second 0 -Millisecond 0
            $result.datetime -eq $date | Should Be $true
        }
    }

    Context "Property: char" {
        It 'Has a column called "char"' {
            $result.Columns.ColumnName.Contains('char') | Should Be $true 
        }
        It 'Has a [char] data type on the column "char"' {
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'char' | Select-Object -ExpandProperty 'DataType' | Should Be 'char'
        }
        It "Has the following char: T" {
            $result.char | Should Be "T"
        }
    }

    Context "Property: true" {
        It 'Has a column called "true"' {
            $result.Columns.ColumnName.Contains('true') | Should Be $true 
        }
        It 'Has a [bool] data type on the column "true"' {
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'true' | Select-Object -ExpandProperty 'DataType' | Should Be 'bool'
        }
        It "Has the following bool: true" {
            $result.true | Should Be $true
        }
    }

    Context "Property: false" {
        It 'Has a column called "false"' {
            $result.Columns.ColumnName.Contains('false') | Should Be $true 
        }
        It 'Has a [bool] data type on the column "false"' {
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'false' | Select-Object -ExpandProperty 'DataType' | Should Be 'bool'
        }
        It "Has the following bool: false" {
            $result.false | Should Be $false
        }
    }

    Context "Property: null" {
        It 'Has a column called "null"' {
            $result.Columns.ColumnName.Contains('null') | Should Be $true 
        }
        It 'Has a [bool] data type on the column "null"' {
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'null' | Select-Object -ExpandProperty 'DataType' | Should Be 'bool'
        }
        It "Has the following bool: false" {
            $result.null | Should Be $false #should actually be $null but its hard to compare :)
        }
    }

    Context "Property: string" {
        It 'Has a column called "string"' {
            $result.Columns.ColumnName.Contains('string') | Should Be $true 
        }
        It 'Has a [string] data type on the column "string"' {
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'string' | Select-Object -ExpandProperty 'DataType' | Should Be 'string'
        }
        It "Has the following string: it's a boy!" {
            $result.string | Should Be "it's a boy!"
        }
    }

    Context "Property: UInt64" {
        It 'Has a column called "UInt64"' {
            $result.Columns.ColumnName.Contains('UInt64') | Should Be $true 
        }
        It 'Has a [string] data type on the column "UInt64"' {
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'UInt64' | Select-Object -ExpandProperty 'DataType' | Should Be 'UInt64'
        }
        It "Has the following number: 123456" {
            $result.UInt64 | Should Be 123456
        }
    }

}
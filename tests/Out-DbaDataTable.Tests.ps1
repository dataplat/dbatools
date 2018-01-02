Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
Describe "Testing data table output when using a complex object" {
    $obj = New-Object -TypeName psobject -Property @{
        guid     = [system.guid]'32ccd4c4-282a-4c0d-997c-7b5deb97f9e0'
        timespan = New-TimeSpan -Start 2016-10-30 -End 2017-04-30
        datetime = Get-Date -Year 2016 -Month 10 -Day 30 -Hour 5 -Minute 52 -Second 0 -Millisecond 0
        char     = [System.Char]'T'
        true     = $true
        false    = $false
        null     = [bool]$null
        string   = "it's a boy!"
        UInt64   = [System.UInt64]123456
    }

    $innedobj = New-Object -TypeName psobject -Property @{
        Mission = 'Keep Hank alive'
    }

    Add-Member -Force -InputObject $obj -MemberType NoteProperty -Name myobject -Value $innedobj
    $result = Out-DbaDataTable -InputObject $obj

    Context "Property: guid" {
        It 'Has a column called "guid"' {
            $result.Columns.ColumnName.Contains('guid') | Should Be $true
        }
        It 'Has a [guid] data type on the column "guid"' {
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'guid' | Select-Object -ExpandProperty 'DataType' | Select-Object -ExpandProperty Name | Should Be 'guid'
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
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'timespan' | Select-Object -ExpandProperty 'DataType' | Select-Object -ExpandProperty Name | Should Be 'Int64'
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
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'datetime' | Select-Object -ExpandProperty 'DataType' | Select-Object -ExpandProperty Name | Should Be 'datetime'
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
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'char' | Select-Object -ExpandProperty 'DataType' | Select-Object -ExpandProperty Name | Should Be 'char'
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
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'true' | Select-Object -ExpandProperty 'DataType' | Select-Object -ExpandProperty Name | Should Be 'boolean'
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
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'false' | Select-Object -ExpandProperty 'DataType' | Select-Object -ExpandProperty Name | Should Be 'boolean'
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
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'null' | Select-Object -ExpandProperty 'DataType' | Select-Object -ExpandProperty Name | Should Be 'boolean'
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
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'string' | Select-Object -ExpandProperty 'DataType' | Select-Object -ExpandProperty Name | Should Be 'string'
        }
        It "Has the following string: it's a boy!" {
            $result.string | Should Be "it's a boy!"
        }
    }

    Context "Property: UInt64" {
        It 'Has a column called "UInt64"' {
            $result.Columns.ColumnName.Contains('UInt64') | Should Be $true
        }
        It 'Has a [UInt64] data type on the column "UInt64"' {
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'UInt64' | Select-Object -ExpandProperty 'DataType' | Select-Object -ExpandProperty Name | Should Be 'UInt64'
        }
        It "Has the following number: 123456" {
            $result.UInt64 | Should Be 123456
        }
    }

    Context "Property: myobject" {
        It 'Has a column called "myobject"' {
            $result.Columns.ColumnName.Contains('myobject') | Should Be $true
        }
        It 'Has a [string] data type on the column "myobject"' {
            $result.Columns | Where-Object -Property 'ColumnName' -eq 'myobject' | Select-Object -ExpandProperty 'DataType' | Select-Object -ExpandProperty Name | Should Be 'String'
        }
        It "Has no value" {
            # not sure if this is a feaure. Should probably be changed in the future
            $result.myobject.GetType().FullName | Should Be "System.DBNull"
        }
    }

}

Describe "Testing input parameters" {
    $obj = New-Object -TypeName psobject -Property @{
        timespan = New-TimeSpan -Start 2017-01-01 -End 2017-01-02
    }

    Context "Verifying TimeSpanType" {
        It "Should return '1.00:00:00' when String is used" {
            (Out-DbaDataTable -InputObject $obj -TimeSpanType String).Timespan | Should Be '1.00:00:00'
        }
        It "Should return 864000000000 when Ticks is used" {
            (Out-DbaDataTable -InputObject $obj -TimeSpanType Ticks).Timespan | Should Be 864000000000
        }
        It "Should return 1 when TotalDays is used" {
            (Out-DbaDataTable -InputObject $obj -TimeSpanType TotalDays).Timespan | Should Be 1
        }
        It "Should return 24 when TotalHours is used" {
            (Out-DbaDataTable -InputObject $obj -TimeSpanType TotalHours).Timespan | Should Be 24
        }
        It "Should return 86400000 when TotalMilliseconds is used" {
            (Out-DbaDataTable -InputObject $obj -TimeSpanType TotalMilliseconds).Timespan | Should Be 86400000
        }
        It "Should return 1440 when TotalMinutes is used" {
            (Out-DbaDataTable -InputObject $obj -TimeSpanType TotalMinutes).Timespan | Should Be 1440
        }
        It "Should return 86400 when TotalSeconds is used" {
            (Out-DbaDataTable -InputObject $obj -TimeSpanType TotalSeconds).Timespan | Should Be 86400
        }
    }

    Context "Verifying IgnoreNull" {
        # To be able to force null
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

        It "Returns message if Null value in pipeline when IgnoreNull is set" {
            $null = returnnull | Out-DbaDataTable -IgnoreNull -WarningVariable warn -WarningAction SilentlyContinue
            $warn.message | Should Match 'The InputObject from the pipe is null'
        }

        It "Returns warning if Null value in array when IgnoreNull is set" {
            $null = Out-DbaDataTable -InputObject (returnnull) -IgnoreNull -WarningVariable warn -WarningAction SilentlyContinue
            $warn.message | Should Match 'Object in array is null'
        }

        It "Does not create row if null is in array when IgnoreNull is set" {
            $result = Out-DbaDataTable -InputObject (returnnull) -IgnoreNull -WarningAction SilentlyContinue
            $result.Rows.Count | Should Be 2
        }

        It "Does not create row if null is in pipeline when IgnoreNull is set" {
            $result = returnnull | Out-DbaDataTable -IgnoreNull -WarningAction SilentlyContinue
            $result.Rows.Count | Should Be 2
        }

        It "Returns empty row when null value is provided (without IgnoreNull)" {
            $result = Out-DbaDataTable -InputObject (returnnull)
            $result.Name[0] | Should Be 1
            $result.Name[1].GetType().FullName | Should Be 'System.DBNull'
            $result.Name[2] | Should Be 3
        }

        It "Returns empty row when null value is passed in pipe (without IgnoreNull)" {
            $result = returnnull | Out-DbaDataTable
            $result.Name[0] | Should Be 1
            $result.Name[1].GetType().FullName | Should Be 'System.DBNull'
            $result.Name[2] | Should Be 3
        }
    }

    Context "Verifying Silent" {
        # To be able to force null
        function returnnull {
            New-Object -TypeName psobject -Property @{ Name = 1 }
            $null
            New-Object -TypeName psobject -Property @{ Name = 3 }
        }

        It "Suppresses warning messages when Silent is used" {
            $null = Out-DbaDataTable -InputObject (returnnull) -IgnoreNull -EnableException -WarningVariable warn -WarningAction SilentlyContinue
            $warn.message -eq $null | Should Be $true
        }
    }

    Context "Verifying script properties returning null" {

        It "Returns string column if a script property returns null" {
            $myobj = New-Object -TypeName psobject -Property @{ Name = 'Test' }
            $myobj | Add-Member -Force -MemberType ScriptProperty -Name ScriptNothing -Value { $null }
            $r = Out-DbaDataTable -InputObject $myobj
            ($r.Columns | Where-Object ColumnName -eq ScriptNothing | Select-Object -ExpandProperty DataType).ToString() | Should Be 'System.String'

        }
    }
}

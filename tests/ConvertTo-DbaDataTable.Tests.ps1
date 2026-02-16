#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "ConvertTo-DbaDataTable",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "InputObject",
                "TimeSpanType",
                "SizeType",
                "IgnoreNull",
                "Raw",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag UnitTests, "DataTableOutput" {
    BeforeAll {
        $obj = New-Object -TypeName psobject -Property @{
            guid             = [system.guid]"32ccd4c4-282a-4c0d-997c-7b5deb97f9e0"
            timespan         = New-TimeSpan -Start 2016-10-30 -End 2017-04-30
            datetime         = Get-Date -Year 2016 -Month 10 -Day 30 -Hour 5 -Minute 52 -Second 0 -Millisecond 0
            char             = [System.Char]"T"
            true             = $true
            false            = $false
            null             = $null
            string           = "it's a boy."
            UInt64           = [System.UInt64]123456
            dbadatetime      = [dbadatetime[]]$(Get-Date -Year 2024 -Month 05 -Day 19 -Hour 5 -Minute 52 -Second 0 -Millisecond 0)
            dbadatetimeArray = [dbadatetime[]]($(Get-Date -Year 2024 -Month 05 -Day 19 -Hour 5 -Minute 52 -Second 0 -Millisecond 0), $(Get-Date -Year 2024 -Month 05 -Day 19 -Hour 5 -Minute 52 -Second 0 -Millisecond 0).AddHours(1))
            inlining         = [PSCustomObject]@{Mission = "Keep Hank alive" }
            inlining2        = [psobject]@{Mission = "Keep Hank alive" }
        }

        $innedobj = New-Object -TypeName psobject -Property @{
            Mission = "Keep Hank alive"
        }

        Add-Member -Force -InputObject $obj -MemberType NoteProperty -Name myObject -Value $innedobj
        $result = ConvertTo-DbaDataTable -InputObject $obj -OutVariable "global:dbatoolsciOutput"

        $firstRow = $result[0].Rows[0]
    }
    Context "Lengths" {
        It "Count of the Rows" {
            $result.Rows.Count | Should -Be 1
        }
    }


    Context "Property: guid" {
        It "Has a column called 'guid'" {
            $result.Columns.ColumnName | Should -Contain "guid"
        }
        It "Has a [guid] data type on the column 'guid'" {
            $firstRow.guid | Should -BeOfType [System.guid]
        }
        It "Has the following guid: '32ccd4c4-282a-4c0d-997c-7b5deb97f9e0'" {
            $firstRow.guid | Should -Be "32ccd4c4-282a-4c0d-997c-7b5deb97f9e0"
        }
    }

    Context "Property: timespan" {
        It "Has a column called 'timespan'" {
            $result.Columns.ColumnName | Should -Contain "timespan"
        }
        It "Has a [long] data type on the column 'timespan'" {
            $firstRow.timespan | Should -BeOfType [System.Int64]
        }
        It "Has the following timespan: 15724800000" {
            $firstRow.timespan | Should -Be 15724800000
        }
    }

    Context "Property: datetime" {
        It "Has a column called 'datetime'" {
            $result.Columns.ColumnName | Should -Contain "datetime"
        }
        It "Has a [datetime] data type on the column 'datetime'" {
            $firstRow.datetime | Should -BeOfType [System.DateTime]
        }
        It "Has the following datetime: 2016-10-30 05:52:00.000" {
            $date = Get-Date -Year 2016 -Month 10 -Day 30 -Hour 5 -Minute 52 -Second 0 -Millisecond 0
            $firstRow.datetime -eq $date | Should -Be $true
        }
    }

    Context "Property: char" {
        It "Has a column called 'char'" {
            $result.Columns.ColumnName | Should -Contain "char"
        }
        It "Has a [char] data type on the column 'char'" {
            $firstRow.char | Should -BeOfType [System.Char]
        }
        It "Has the following char: T" {
            $firstRow.char | Should -Be "T"
        }
    }

    Context "Property: true" {
        It "Has a column called 'true'" {
            $result.Columns.ColumnName | Should -Contain "true"
        }
        It "Has a [bool] data type on the column 'true'" {
            $firstRow.true | Should -BeOfType [System.Boolean]
        }
        It "Has the following bool: true" {
            $firstRow.true | Should -Be $true
        }
    }

    Context "Property: false" {
        It "Has a column called 'false'" {
            $result.Columns.ColumnName | Should -Contain "false"
        }
        It "Has a [bool] data type on the column 'false'" {
            $firstRow.false | Should -BeOfType [System.Boolean]
        }
        It "Has the following bool: false" {
            $firstRow.false | Should -Be $false
        }
    }

    Context "Property: null" {
        It "Has a column called 'null'" {
            $result.Columns.ColumnName | Should -Contain "null"
        }
        It "Has a [null] data type on the column 'null'" {
            $firstRow.null | Should -BeOfType [System.DBNull]
        }
        It "Has no value" {
            $firstRow.null | Should -BeNullOrEmpty
        }
    }

    Context "Property: string" {
        It "Has a column called 'string'" {
            $result.Columns.ColumnName | Should -Contain "string"
        }
        It "Has a [string] data type on the column 'string'" {
            $firstRow.string | Should -BeOfType [System.String]
        }
        It "Has the following string: it's a boy." {
            $firstRow.string | Should -Be "it's a boy."
        }
    }

    Context "Property: UInt64" {
        It "Has a column called 'UInt64'" {
            $result.Columns.ColumnName | Should -Contain "UInt64"
        }
        It "Has a [UInt64] data type on the column 'UInt64'" {
            $firstRow.UInt64 | Should -BeOfType [System.UInt64]
        }
        It "Has the following number: 123456" {
            $firstRow.UInt64 | Should -Be 123456
        }
    }

    Context "Property: myObject" {
        It "Has a column called 'myObject'" {
            $result.Columns.ColumnName | Should -Contain "myObject"
        }
    }

    Context "Property: dbadatetime" {
        It "Has a column called 'dbadatetime'" {
            $result.Columns.ColumnName | Should -Contain "dbadatetime"
        }
        It "Has a [System.String] data type on the column 'myObject'" {
            $firstRow.dbadatetime | Should -BeOfType [System.String]
        }
        It "Has the following dbadatetime: 2024-05-19 05:52:00.000" {
            $date = Get-Date -Year 2024 -Month 5 -Day 19 -Hour 5 -Minute 52 -Second 0 -Millisecond 0
            [datetime]$result.dbadatetime -eq $date | Should -Be $true
        }
    }

    Context "Property: dbadatetimeArray" {
        It "Has a column called 'dbadatetimeArray'" {
            $result.Columns.ColumnName | Should -Contain "dbadatetimeArray"
        }
        It "Has a [System.String] data type on the column 'myObject'" {
            $firstRow.dbadatetimeArray | Should -BeOfType [System.String]
        }
        It "Has the following dbadatetimeArray converted to strings: 2024-05-19 05:52:00.000, 2024-05-19 06:52:00.000" {
            $string = "2024-05-19 05:52:00.000, 2024-05-19 06:52:00.000"
            $firstRow.dbadatetimeArray -eq $string | Should -Be $true
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0].GetType().FullName | Should -Be "System.Data.DataTable"
        }

        It "Should have columns matching input object properties" {
            $expectedColumns = @(
                "char",
                "datetime",
                "dbadatetime",
                "dbadatetimeArray",
                "false",
                "guid",
                "inlining",
                "inlining2",
                "myObject",
                "null",
                "string",
                "timespan",
                "true",
                "UInt64"
            )
            $actualColumns = $global:dbatoolsciOutput[0].Columns.ColumnName | Sort-Object
            Compare-Object -ReferenceObject ($expectedColumns | Sort-Object) -DifferenceObject $actualColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.Data\.DataTable"
        }
    }
}

Describe $CommandName -Tag UnitTests, "InputParameters" {
    BeforeAll {
        $obj = New-Object -TypeName psobject -Property @{
            timespan = New-TimeSpan -Start 2017-01-01 -End 2017-01-02
        }
    }

    Context "Verifying TimeSpanType" {
        It "Should return '1.00:00:00' when String is used" {
            (ConvertTo-DbaDataTable -InputObject $obj -TimeSpanType String).Timespan | Should -Be "1.00:00:00"
        }
        It "Should return 864000000000 when Ticks is used" {
            (ConvertTo-DbaDataTable -InputObject $obj -TimeSpanType Ticks).Timespan | Should -Be 864000000000
        }
        It "Should return 1 when TotalDays is used" {
            (ConvertTo-DbaDataTable -InputObject $obj -TimeSpanType TotalDays).Timespan | Should -Be 1
        }
        It "Should return 24 when TotalHours is used" {
            (ConvertTo-DbaDataTable -InputObject $obj -TimeSpanType TotalHours).Timespan | Should -Be 24
        }
        It "Should return 86400000 when TotalMilliseconds is used" {
            (ConvertTo-DbaDataTable -InputObject $obj -TimeSpanType TotalMilliseconds).Timespan | Should -Be 86400000
        }
        It "Should return 1440 when TotalMinutes is used" {
            (ConvertTo-DbaDataTable -InputObject $obj -TimeSpanType TotalMinutes).Timespan | Should -Be 1440
        }
        It "Should return 86400 when TotalSeconds is used" {
            (ConvertTo-DbaDataTable -InputObject $obj -TimeSpanType TotalSeconds).Timespan | Should -Be 86400
        }
    }

    Context "Verifying IgnoreNull" {
        BeforeAll {
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

    Context "Verifying Silent" {
        BeforeAll {
            # To be able to force null
            function returnnull {
                New-Object -TypeName psobject -Property @{ Name = 1 }
                $null
                New-Object -TypeName psobject -Property @{ Name = 3 }
            }
        }

        It "Suppresses warning messages when Silent is used" {
            $null = ConvertTo-DbaDataTable -InputObject (returnnull) -IgnoreNull -EnableException -WarningVariable warn -WarningAction SilentlyContinue 3> $null
            $warn | Should -BeNullOrEmpty
        }
    }

    Context "Verifying script properties returning null" {
        It "Returns string column if a script property returns null" {
            $myobj = New-Object -TypeName psobject -Property @{ Name = "Test" }
            $myobj | Add-Member -Force -MemberType ScriptProperty -Name ScriptNothing -Value { $null }
            $r = ConvertTo-DbaDataTable -InputObject $myobj
            ($r.Columns | Where-Object ColumnName -eq ScriptNothing | Select-Object -ExpandProperty DataType).ToString() | Should -Be "System.String"
        }
    }

    Context "Verifying a datatable gets cloned when passed in" {
        BeforeAll {
            $obj = New-Object -TypeName psobject -Property @{
                col1 = "col1"
                col2 = "col2"
            }
            $first = $obj | ConvertTo-DbaDataTable
            $second = $first | ConvertTo-DbaDataTable
        }

        It "Should have the same columns" {
            # does not add ugly RowError,RowState Table, ItemArray, HasErrors
            $firstColumns = ($first.Columns.ColumnName | Sort-Object) -Join ","
            $secondColumns = ($second.Columns.ColumnName | Sort-Object) -Join ","
            $firstColumns | Should -Be $secondColumns
        }
    }
}
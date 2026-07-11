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
        $result = ConvertTo-DbaDataTable -InputObject $obj

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

Describe "$CommandName compiled-cmdlet characterization" -Tag IntegrationTests {
    BeforeAll {
        # Characterization scenarios for the migration gate (which executes -Tag IntegrationTests):
        # ConvertTo-DbaDataTable is pure compute, so these run everywhere (lab and AppVeyor) with no
        # SQL instance. Expected values were captured against the current script function on both
        # editions (PS 5.1 and PS 7) before the compiled-cmdlet flip; assertions are edition-agnostic.
        $charAlpha = New-Object -TypeName psobject -Property @{ Name = [int]1 }
        $charOmega = New-Object -TypeName psobject -Property @{ Name = [int]3 }
        $hetFirst = New-Object -TypeName psobject -Property @{ Name = "first" }
        $hetSecond = New-Object -TypeName psobject -Property @{ Name = "second" }
        $numGood = New-Object -TypeName psobject -Property @{ Num = [int]1 }
        $numBad = New-Object -TypeName psobject -Property @{ Num = "not-a-number" }
        $tagBag = New-Object -TypeName psobject -Property @{ Tags = @("a", "b", "c") }
        $emptyStringBag = New-Object -TypeName psobject -Property @{ Name = "" }
        $sameA = New-Object -TypeName psobject -Property @{ V = "same" }
        $sameB = New-Object -TypeName psobject -Property @{ V = "same" }
        $lastC = New-Object -TypeName psobject -Property @{ V = "diff" }
        $rawBag = New-Object -TypeName psobject -Property @{ Num = [int]5 }
        $sizeBag = New-Object -TypeName psobject -Property @{ Size = [dbasize]1048576 }
        Add-Member -InputObject $hetSecond -MemberType NoteProperty -Name Extra -Value ([int]42)
        Add-Member -InputObject $emptyStringBag -MemberType NoteProperty -Name Other -Value "x"
    }

    Context "Output shape and null handling" {
        It "Emits a single DataTable object and keeps a piped null as an empty row" {
            $result = @($charAlpha, $null, $charOmega) | ConvertTo-DbaDataTable
            $result -is [System.Data.DataTable] | Should -BeTrue
            $result.Rows.Count | Should -Be 3
            $result.Rows[0].Name | Should -Be 1
            $result.Rows[1].Name.GetType().FullName | Should -Be "System.DBNull"
            $result.Rows[2].Name | Should -Be 3
        }

        It "Converts a lone piped null into one empty row with no columns" {
            $result = $null | ConvertTo-DbaDataTable
            $result.Rows.Count | Should -Be 1
            $result.Columns.Count | Should -Be 0
        }

        It "Drops a lone piped null entirely when IgnoreNull is set" {
            $result = $null | ConvertTo-DbaDataTable -IgnoreNull
            $result.Rows.Count | Should -Be 0
        }

        It "Binds InputObject positionally" {
            $result = ConvertTo-DbaDataTable $charAlpha
            $result.Rows.Count | Should -Be 1
            $result.Rows[0].Name | Should -Be 1
        }
    }

    Context "Column creation" {
        It "Adds a typed column on the fly when a later object introduces a new property" {
            $result = ConvertTo-DbaDataTable -InputObject @($hetFirst, $hetSecond) -WarningVariable charWarn -WarningAction SilentlyContinue
            ($result.Columns | Where-Object ColumnName -eq "Extra").DataType.FullName | Should -Be "System.Int32"
            $result.Rows[0].Extra.GetType().FullName | Should -Be "System.DBNull"
            $result.Rows[1].Extra | Should -Be 42
            $charWarn | Should -BeNullOrEmpty
        }

        It "Joins an object array property into a comma separated string column" {
            $result = ConvertTo-DbaDataTable -InputObject $tagBag
            ($result.Columns | Where-Object ColumnName -eq "Tags").DataType.FullName | Should -Be "System.String"
            $result.Rows[0].Tags | Should -Be "a, b, c"
        }

        It "Creates all columns as strings when Raw is set" {
            $result = ConvertTo-DbaDataTable -InputObject $rawBag -Raw
            ($result.Columns | Where-Object ColumnName -eq "Num").DataType.FullName | Should -Be "System.String"
            $result.Rows[0].Num | Should -Be "5"
        }

        It "Converts a dbasize property to Int64 bytes by default" {
            $result = ConvertTo-DbaDataTable -InputObject $sizeBag
            ($result.Columns | Where-Object ColumnName -eq "Size").DataType.FullName | Should -Be "System.Int64"
            $result.Rows[0].Size | Should -Be 1048576
        }
    }

    Context "Value handling" {
        It "Leaves a zero length string value as DBNull" {
            $result = ConvertTo-DbaDataTable -InputObject $emptyStringBag
            $result.Rows[0].Name.GetType().FullName | Should -Be "System.DBNull"
            $result.Rows[0].Other | Should -Be "x"
        }

        It "Warns and keeps the row with a DBNull cell when a value cannot convert to the column type" {
            $result = ConvertTo-DbaDataTable -InputObject @($numGood, $numBad) -WarningVariable charWarn -WarningAction SilentlyContinue
            $result.Rows.Count | Should -Be 2
            $result.Rows[1].Num.GetType().FullName | Should -Be "System.DBNull"
            $charWarn | Should -Match "Failed to add property Num"
        }

        It "Throws instead of warning when EnableException is set and a value cannot convert" {
            { ConvertTo-DbaDataTable -InputObject @($numGood, $numBad) -EnableException -WarningAction SilentlyContinue } | Should -Throw "*was not in a correct format*"
        }
    }

    Context "DataRow passthrough" {
        It "Merges piped DataRows through the distinct view so duplicate rows collapse" {
            $dedupSource = ConvertTo-DbaDataTable -InputObject @($sameA, $sameB, $lastC)
            $dedupSource.Rows.Count | Should -Be 3
            $cloned = $dedupSource | ConvertTo-DbaDataTable
            $cloned.Rows.Count | Should -Be 2
            ($cloned.Rows | ForEach-Object { $PSItem.V }) -join "," | Should -Be "same,diff"
        }
    }
}